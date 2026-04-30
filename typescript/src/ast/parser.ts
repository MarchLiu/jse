/**
 * JSON to AST parser for JSE.
 *
 * Following the design in docs/regular.md:
 * - Recognizes symbols (strings starting with $ but not $$)
 * - Identifies expressions in arrays and objects
 * - Creates AST nodes with proper environment capture
 */

import type { JseValue } from "../types.js";
import type { Env } from "../env.js";
import {
  SymbolNode,
  ArrayNode,
  ObjectNode,
  ObjectExpressionNode,
  QuoteNode,
  LiteralNode,
} from "./nodes.js";

/**
 * Check if string is a JSE symbol.
 * Symbols start with $ but not $$.
 * Wildcard $* is not a symbol.
 */
function isSymbol(s: string): boolean {
  // Wildcard $* is a literal string, not a symbol
  if (s === "$*") {
    return false;
  }
  return s.startsWith("$") && !s.startsWith("$$");
}

/**
 * Unescape $$-prefixed string.
 */
function unescape(s: string): string {
  if (s.startsWith("$$")) {
    return s.slice(1);
  }
  return s;
}

/**
 * Parse JSON values into JSE AST nodes.
 */
export class Parser {
  constructor(private _env: Env) {}

  /**
   * Parse JSON value into AST node or return primitive.
   */
  parse(expr: JseValue): JseValue {
    // Primitives - wrap in LiteralNode
    if (expr === null || typeof expr === "number" || typeof expr === "boolean") {
      return new LiteralNode(expr, this._env);
    }

    // Strings - check if symbol
    if (typeof expr === "string") {
      if (isSymbol(expr)) {
        return new SymbolNode(expr, this._env);
      }
      return new LiteralNode(unescape(expr), this._env);
    }

    // Arrays - check for expression form
    if (Array.isArray(expr)) {
      return this.parseList(expr);
    }

    // Objects - check for expression form
    if (typeof expr === "object" && expr !== null) {
      return this.parseDict(expr as Record<string, JseValue>);
    }

    // Unknown type - wrap as literal
    return new LiteralNode(expr, this._env);
  }

  /**
   * Parse list expression.
   * Forms:
   * - ["$quote", x] -> QuoteNode
   * - [symbol, ...] -> ArrayNode (function call)
   * - [...] -> ArrayNode (regular array)
   */
  private parseList(lst: JseValue[]): JseValue {
    if (lst.length === 0) {
      // Empty list
      return new ArrayNode([], this._env);
    }

    const first = lst[0];

    // Special case: $quote
    if (first === "$quote") {
      // ["$quote", x] - return x unevaluated
      const value = lst.length > 1 ? lst[1] : null;
      return new QuoteNode(value, this._env);
    }

    // Check if this is a function call form
    if (typeof first === "string" && isSymbol(first)) {
      // [symbol, args...] - function call
      const elements = lst.map((e) => this.parse(e));
      return new ArrayNode(elements, this._env);
    }

    // Regular array - evaluate all elements
    const elements = lst.map((e) => this.parse(e));
    return new ArrayNode(elements, this._env);
  }

  /**
   * Parse dict expression.
   * Forms:
   * - {"$quote": x} -> QuoteNode
   * - {symbol: value, ...} -> ObjectExpressionNode (exactly one symbol key)
   * - {...} -> ObjectNode with regular keys
   */
  private parseDict(d: Record<string, JseValue>): JseValue {
    // Find symbol keys
    const symbolKeys = Object.keys(d).filter((k) => isSymbol(k));

    if (symbolKeys.length === 0) {
      // Regular object - parse all values
      const result: Record<string, JseValue> = {};
      for (const [k, v] of Object.entries(d)) {
        result[unescape(k)] = this.parse(v);
      }
      return new ObjectNode(result, this._env);
    }

    if (symbolKeys.length === 1) {
      // Operator form: {"$operator": value, "meta": ...}
      const operator = symbolKeys[0];

      // Special case: $quote
      if (operator === "$quote") {
        return new QuoteNode(d[operator], this._env);
      }

      // Special case: $sql — pass raw JSON directly
      if (operator === "$sql") {
        const metadata: Record<string, JseValue> = {};
        for (const [k, v] of Object.entries(d)) {
          if (k !== operator) {
            metadata[unescape(k)] = v;
          }
        }
        return new ObjectExpressionNode(operator, new LiteralNode(d[operator], this._env), metadata, this._env);
      }

      // Parse the value
      const parsedValue = this.parse(d[operator]);

      // Parse metadata (other keys)
      const metadata: Record<string, JseValue> = {};
      for (const [k, v] of Object.entries(d)) {
        if (k !== operator) {
          metadata[unescape(k)] = this.parse(v);
        }
      }

      return new ObjectExpressionNode(operator, parsedValue, metadata, this._env);
    }

    // Multiple symbol keys - error per formal semantics
    throw new Error("JSE structure error: object cannot have multiple operator keys");
  }
}
