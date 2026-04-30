/**
 * Concrete AST node implementations for JSE.
 *
 * Following the design in docs/regular.md:
 * - SymbolNode: Represents a symbol reference like $x
 * - ArrayNode: Represents [operator, args...] function call
 * - ObjectNode: Represents plain object {key: value}
 * - ObjectExpressionNode: Represents {"$operator": value} operator call
 * - QuoteNode: Represents quoted (unevaluated) expression
 * - LambdaNode: Represents lambda function with closure
 * - LiteralNode: Represents a literal value
 */

import type { JseValue, Functor } from "../types.js";
import { Env } from "../env.js";
import { AstNode } from "./base.js";

/**
 * Represents a symbol reference like $x.
 * When applied, looks up the symbol in the call-time environment.
 */
export class SymbolNode extends AstNode {
  constructor(private _name: string, env: Env) {
    super(env);
  }

  get name(): string {
    return this._name;
  }

  apply(env: Env): JseValue {
    const value = env.resolve(this._name);
    if (value === undefined) {
      throw new Error(`Symbol '${this._name}' not found`);
    }
    return value;
  }
}

/**
 * Represents an array expression.
 * Can be either:
 * - A function call: [operator, args...]
 * - A regular array: [elements...]
 */
export class ArrayNode extends AstNode {
  constructor(private _elements: JseValue[], env: Env) {
    super(env);
  }

  get elements(): JseValue[] {
    return this._elements;
  }

  apply(env: Env): JseValue {
    if (this._elements.length === 0) {
      return [];
    }

    const first = this._elements[0];

    // Check if this is a function call form
    if (first instanceof SymbolNode) {
      // Look up the functor
      const functor = env.resolve(first.name);
      if (functor === undefined) {
        throw new Error(`Unknown operator: ${first.name}`);
      }

      // Special forms: don't evaluate all arguments
      // $def, $defn, $lambda, $quote need unevaluated symbols/expressions
      const specialForms = new Set(["$def", "$defn", "$lambda", "$quote"]);
      if (specialForms.has(first.name)) {
        // Pass arguments unevaluated (functor will handle)
        if (typeof functor === "function") {
          return (functor as Functor)(env, ...this._elements.slice(1));
        }
        return functor;
      }

      // Regular functors: evaluate arguments first
      const evaluatedArgs = this._elements.slice(1).map((arg) => env.eval(arg));

      // Call the functor
      if (typeof functor === "function") {
        return (functor as Functor)(env, ...evaluatedArgs);
      }
      return functor;
    }

    // Regular array - evaluate all elements
    return this._elements.map((elem) => env.eval(elem));
  }
}

/**
 * Represents a plain object with key-value pairs.
 * Form: {key: value, ...}
 */
export class ObjectNode extends AstNode {
  constructor(private _dict: Record<string, JseValue>, env: Env) {
    super(env);
  }

  get dict(): Record<string, JseValue> {
    return this._dict;
  }

  apply(env: Env): JseValue {
    const result: Record<string, JseValue> = {};
    for (const [k, v] of Object.entries(this._dict)) {
      result[k] = env.eval(v);
    }
    return result;
  }
}

/**
 * Deep evaluate a value, handling nested arrays and AST nodes.
 */
function deepEval(env: Env, value: JseValue): JseValue {
  // First, evaluate any AST node
  const evaluated = env.eval(value);

  // If result is an array, recursively evaluate its elements
  if (Array.isArray(evaluated)) {
    return evaluated.map((item) => deepEval(env, item));
  }

  // If result is a plain object (not AST node), evaluate its values
  if (typeof evaluated === "object" && evaluated !== null && !(evaluated instanceof AstNode)) {
    const result: Record<string, JseValue> = {};
    for (const [k, v] of Object.entries(evaluated)) {
      result[k] = deepEval(env, v);
    }
    return result;
  }

  return evaluated;
}

/**
 * Represents an object expression with operator key.
 * Form: {"$operator": value, "meta": ...}
 */
export class ObjectExpressionNode extends AstNode {
  constructor(
    private _operator: string,
    private _value: JseValue,
    private _metadata: Record<string, JseValue>,
    env: Env
  ) {
    super(env);
  }

  get operator(): string {
    return this._operator;
  }

  get value(): JseValue {
    return this._value;
  }

  get metadata(): Record<string, JseValue> {
    return this._metadata;
  }

  apply(env: Env): JseValue {
    // Look up the functor
    const functor = env.resolve(this._operator);
    if (functor === undefined) {
      throw new Error(`Unknown operator: ${this._operator}`);
    }

    // For object expressions, we need to evaluate the value as arguments
    // If the value is an ArrayNode, we want to evaluate its elements as data,
    // NOT as a function call (which ArrayNode.apply() would do)
    let args: JseValue[];

    if (this._operator === "$expr") {
      // $expr evaluates the whole expression and returns the result
      args = [env.eval(this._value)];
    } else if (this._operator === "$sql") {
      // $sql receives raw JSON (stored in LiteralNode by parser)
      if (this._value instanceof LiteralNode) {
        args = [(this._value as LiteralNode).value];
      } else {
        args = [this._value];
      }
    } else if (this._value instanceof ArrayNode) {
      // Get the elements of the array node
      const elements = this._value.elements;
      // Evaluate each element as data (not as function calls)
      args = elements.map((elem) => deepEval(env, elem));
    } else {
      // For other types, just evaluate normally
      args = [env.eval(this._value)];
    }

    // Set metadata context before calling functor
    env.setMeta(this._metadata);

    try {
      // Call the functor
      if (typeof functor === "function") {
        return (functor as Functor)(env, ...args);
      }
      return functor;
    } finally {
      // Clear metadata context after functor call
      env.clearMeta();
    }
  }
}

/**
 * Represents a quoted (unevaluated) expression.
 * Form: ["$quote", expr] or {"$quote": expr}
 * Returns the expression without evaluation.
 */
export class QuoteNode extends AstNode {
  constructor(private _value: JseValue, env: Env) {
    super(env);
  }

  get value(): JseValue {
    return this._value;
  }

  apply(_env: Env): JseValue {
    // Return quoted value without evaluation
    return this._value;
  }
}

/**
 * Represents a lambda function with closure.
 * Captures construct-time environment for static scoping.
 * When applied, creates new environment with closure as parent.
 */
export class LambdaNode extends AstNode {
  constructor(
    private _params: string[],
    private _body: JseValue,
    closureEnv: Env
  ) {
    super(closureEnv);
  }

  get params(): string[] {
    return this._params;
  }

  get body(): JseValue {
    return this._body;
  }

  apply(env: Env, ...args: JseValue[]): JseValue {
    if (args.length !== this._params.length) {
      throw new Error(
        `Lambda expects ${this._params.length} args, got ${args.length}`
      );
    }

    // Create new environment for this call
    // Parent is closure_env (static scoping!)
    const callEnv = new Env(this._env);

    // Bind parameters to arguments
    for (let i = 0; i < this._params.length; i++) {
      callEnv.set(this._params[i], args[i]);
    }

    // Evaluate body in call environment
    return callEnv.eval(this._body);
  }
}

/**
 * Represents a literal value (number, string, bool, null).
 * Returns itself when applied (no evaluation needed).
 */
export class LiteralNode extends AstNode {
  constructor(private _value: JseValue, env: Env) {
    super(env);
  }

  get value(): JseValue {
    return this._value;
  }

  apply(_env: Env): JseValue {
    return this._value;
  }
}
