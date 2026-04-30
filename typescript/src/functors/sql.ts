/**
 * SQL generation functors for JSE.
 *
 * Implements the $sql functor per Issue #3 v4 design.
 * Also retains legacy $query / $pattern for backward compatibility.
 */

import type { JseValue } from "../types.js";
import { Env } from "../env.js";
import { Parser } from "../ast/parser.js";
import type { AstNodeLike } from "../types.js";

export const QUERY_FIELDS = "subject, predicate, object, meta";

// ============================================================
// Subquery detection
// ============================================================

function isSubquery(value: unknown): boolean {
  if (!Array.isArray(value) || value.length === 0) return false;
  return value.every(
    (item) =>
      Array.isArray(item) &&
      item.length > 0 &&
      typeof item[0] === "string" &&
      item[0].startsWith("$")
  );
}

// ============================================================
// String utilities
// ============================================================

function isSymbolStr(s: string): boolean {
  if (s === "$*") return false;
  return s.startsWith("$") && !s.startsWith("$$");
}

function isEscapedStr(s: string): boolean {
  return s.startsWith("$$");
}

function sqlQuote(s: string): string {
  return `'${s.replace(/'/g, "''")}'`;
}

function isParenthesized(s: string): boolean {
  if (!s.startsWith("(")) return false;
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "(") depth++;
    else if (s[i] === ")") depth--;
    if (depth === 0) return i === s.length - 1;
  }
  return false;
}

// ============================================================
// Expression → SQL fragment renderer
// ============================================================

function renderExpr(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (Number.isInteger(value)) return value.toString();
    return value.toString();
  }

  if (typeof value === "string") {
    if (isEscapedStr(value)) return sqlQuote("$" + value.slice(2));
    if (isSymbolStr(value)) return value.slice(1);
    return sqlQuote(value);
  }

  if (Array.isArray(value)) {
    if (value.length === 0) return "";
    if (isSubquery(value)) return renderSubquery(value);
    const first = value[0];
    if (typeof first === "string" && first.startsWith("$") && !first.startsWith("$$")) {
      return renderListExpr(value);
    }
    return value.map(renderExpr).join(", ");
  }

  if (typeof value === "object" && value !== null) {
    return renderDictExpr(value as Record<string, unknown>);
  }

  return String(value);
}

function renderDictExpr(d: Record<string, unknown>): string {
  const keys = Object.keys(d);
  if (keys.length === 0) return "";

  const opKeys = keys.filter((k) => isSymbolStr(k));
  if (opKeys.length === 0) {
    return keys.map((k) => `${renderKey(k)} = ${renderExpr(d[k])}`).join(", ");
  }
  if (opKeys.length > 1) {
    return keys.map((k) => `${renderKey(k)} = ${renderExpr(d[k])}`).join(", ");
  }

  const op = opKeys[0];
  if (op === "$symbol") return `"${d[op]}"`;
  return renderExpr(d[op]);
}

function renderKey(k: unknown): string {
  if (typeof k === "string") {
    if (isSymbolStr(k)) return k.slice(1);
    if (isEscapedStr(k)) return "$" + k.slice(2);
    return k;
  }
  return String(k);
}

function renderListExpr(lst: unknown[]): string {
  if (lst.length === 0) return "";
  const op = lst[0];
  if (typeof op !== "string") return lst.map(renderExpr).join(", ");
  if (op.startsWith("$$")) return lst.map(renderExpr).join(", ");

  return renderFunc(op, lst.slice(1));
}

// ============================================================
// Function dispatch
// ============================================================

function renderFunc(op: string, args: unknown[]): string {
  switch (op) {
    case "$as": return renderAs(args);
    case "$count": return renderCount(args);
    case "$sum": return renderAgg("sum", args);
    case "$avg": return renderAgg("avg", args);
    case "$max": return renderAgg("max", args);
    case "$min": return renderAgg("min", args);
    case "$eq": return renderBinary("=", args);
    case "$ne": return renderBinary("!=", args);
    case "$gt": return renderBinary(">", args);
    case "$gte": return renderBinary(">=", args);
    case "$lt": return renderBinary("<", args);
    case "$lte": return renderBinary("<=", args);
    case "$like": return renderBinary("like", args);
    case "$is": return renderIs(args);
    case "$is-not": return renderIsNot(args);
    case "$and": return renderLogical("and", args);
    case "$or": return renderLogical("or", args);
    case "$in": return renderIn(args);
    case "$case": return renderCase(args);
    case "$excluded": return renderExcluded(args);
  }
  const opName = op.slice(1);
  return `${opName}(${args.map(renderExpr).join(", ")})`;
}

function renderAs(args: unknown[]): string {
  if (args.length < 2) return "";
  const expr = renderExpr(args[0]);
  const alias = renderExpr(args[1]);
  if (Array.isArray(args[0])) return `(${expr}) as ${alias}`;
  if (typeof args[0] === "string" && isSymbolStr(args[0])) return `${args[0].slice(1)} as ${alias}`;
  return `${expr} as ${alias}`;
}

function renderCount(args: unknown[]): string {
  if (args.length === 0) return "count(*)";
  if (typeof args[0] === "string" && args[0] === "$*") return "count(*)";
  return `count(${renderExpr(args[0])})`;
}

function renderAgg(fn: string, args: unknown[]): string {
  if (args.length === 0) return `${fn}(*)`;
  return `${fn}(${renderExpr(args[0])})`;
}

function renderBinary(op: string, args: unknown[]): string {
  if (args.length < 2) return args.length > 0 ? renderExpr(args[0]) : "";
  return `${renderExpr(args[0])} ${op} ${renderExpr(args[1])}`;
}

function renderIs(args: unknown[]): string {
  if (args.length < 2) return "";
  const left = renderExpr(args[0]);
  if (args[1] === null || args[1] === undefined) return `${left} is null`;
  return `${left} is ${renderExpr(args[1])}`;
}

function renderIsNot(args: unknown[]): string {
  if (args.length < 2) return "";
  const left = renderExpr(args[0]);
  if (args[1] === null || args[1] === undefined) return `${left} is not null`;
  return `${left} is not ${renderExpr(args[1])}`;
}

function renderLogical(op: string, args: unknown[]): string {
  if (args.length === 0) return op === "and" ? "true" : "false";
  const parts = args.map((a) => {
    const r = renderExpr(a);
    return isParenthesized(r) ? r : `(${r})`;
  });
  return `(${parts.join(` ${op} `)})`;
}

function renderIn(args: unknown[]): string {
  if (args.length < 2) return "";
  const col = renderExpr(args[0]);
  const val = args[1];
  if (Array.isArray(val) && isSubquery(val)) {
    return `${col} in (${renderSubquery(val)})`;
  }
  if (Array.isArray(val)) {
    return `${col} in (${val.map(renderExpr).join(", ")})`;
  }
  return `${col} in (${renderExpr(val)})`;
}

function renderCase(args: unknown[]): string {
  const parts = ["case"];
  let elseVal: string | null = null;
  for (const arg of args) {
    if (Array.isArray(arg) && arg.length > 0 && typeof arg[0] === "string") {
      if (arg[0] === "$when" && arg.length >= 3) {
        parts.push(`when ${renderExpr(arg[1])} then ${renderExpr(arg[2])}`);
      } else if (arg[0] === "$else" && arg.length >= 2) {
        elseVal = renderExpr(arg[1]);
      }
    }
  }
  if (elseVal !== null) parts.push(`else ${elseVal}`);
  parts.push("end");
  return parts.join(" ");
}

function renderExcluded(args: unknown[]): string {
  if (args.length === 0) return "excluded";
  return `excluded.${renderExpr(args[0])}`;
}

// ============================================================
// Subquery rendering
// ============================================================

function renderSubquery(clauses: unknown[]): string {
  return clauses
    .filter((c): c is unknown[] => Array.isArray(c))
    .map((c) => renderClause(c))
    .filter(Boolean)
    .join(" ");
}

// ============================================================
// Clause renderer
// ============================================================

function renderClause(clause: unknown[]): string {
  if (clause.length === 0) return "";
  const kw = clause[0];
  if (typeof kw !== "string" || !kw.startsWith("$")) return "";
  const args = clause.slice(1);

  switch (kw) {
    case "$select":
      return `select ${args.map(renderExpr).join(", ")}`;
    case "$from":
      return `from ${renderTable(args)}`;
    case "$join":
      return `join ${renderJoin(args)}`;
    case "$left-join":
      return `left join ${renderJoin(args)}`;
    case "$right-join":
      return `right join ${renderJoin(args)}`;
    case "$full-join":
      return `full join ${renderJoin(args)}`;
    case "$cross-join":
      return `cross join ${renderTable(args)}`;
    case "$where":
      return args.length > 0 ? `where ${renderExpr(args[0])}` : "";
    case "$group-by":
      return args.length > 0 ? `group by ${renderExpr(args[0])}` : "";
    case "$having":
      return args.length > 0 ? `having ${renderExpr(args[0])}` : "";
    case "$order-by":
      return renderOrderBy(args);
    case "$limit":
      return args.length > 0 ? `limit ${renderExpr(args[0])}` : "";
    case "$offset":
      return args.length > 0 ? `offset ${renderExpr(args[0])}` : "";
    case "$with":
      return renderWith(args);
    case "$insert-into":
      return renderInsertInto(args);
    case "$values":
      return `values (${args.map(renderExpr).join(", ")})`;
    case "$update":
      return `update ${renderTable(args)}`;
    case "$set":
      return renderSet(args);
    case "$delete-from":
      return `delete from ${renderTable(args)}`;
    case "$on-conflict":
      return args.length > 0 ? `on conflict (${renderExpr(args[0])})` : "";
    case "$do-update":
      return renderDoUpdate(args);
  }
  return kw.slice(1);
}

function renderTable(args: unknown[]): string {
  if (args.length === 0) return "";
  const first = args[0];
  if (Array.isArray(first) && first.length > 0 && first[0] === "$as") {
    return renderListExpr(first);
  }
  return renderExpr(first);
}

function renderJoin(args: unknown[]): string {
  if (args.length === 0) return "";
  const table = renderExpr(args[0]);
  if (args.length >= 2) return `${table} on ${renderExpr(args[1])}`;
  return table;
}

function renderOrderBy(args: unknown[]): string {
  if (args.length === 0) return "";
  const col = renderExpr(args[0]);
  if (args.length >= 2 && typeof args[1] === "string" && isSymbolStr(args[1])) {
    const d = args[1].slice(1);
    if (d === "desc" || d === "asc") return `order by ${col} ${d}`;
  }
  if (args.length >= 2) return `order by ${col} ${renderExpr(args[1])}`;
  return `order by ${col}`;
}

function renderWith(args: unknown[]): string {
  if (args.length === 0 || typeof args[0] !== "object" || args[0] === null) return "";
  const cteDefs = args[0] as Record<string, unknown>;
  const cteParts: string[] = [];
  for (const [cteNameKey, cteClauses] of Object.entries(cteDefs)) {
    const cteName = isSymbolStr(cteNameKey) ? cteNameKey.slice(1) : cteNameKey;
    if (Array.isArray(cteClauses) && cteClauses.length > 0) {
      const inner = (cteClauses as unknown[])
        .filter((c): c is unknown[] => Array.isArray(c))
        .map((c) => renderClause(c))
        .filter(Boolean)
        .join(" ");
      cteParts.push(`${cteName} as (${inner})`);
    }
  }
  if (cteParts.length === 0) return "";
  return `with ${cteParts.join(",\n")}`;
}

function renderInsertInto(args: unknown[]): string {
  if (args.length === 0) return "insert into";
  const table = renderExpr(args[0]);
  if (args.length > 1) {
    const cols = args.slice(1).map(renderExpr).join(", ");
    return `insert into ${table} (${cols})`;
  }
  return `insert into ${table}`;
}

function renderSet(args: unknown[]): string {
  if (args.length === 0 || typeof args[0] !== "object" || args[0] === null) return "";
  const mapping = args[0] as Record<string, unknown>;
  const parts = Object.entries(mapping).map(
    ([col, val]) => `${renderKey(col)} = ${renderExpr(val)}`
  );
  return `set ${parts.join(", ")}`;
}

function renderDoUpdate(args: unknown[]): string {
  if (args.length === 0 || typeof args[0] !== "object" || args[0] === null) return "";
  const mapping = args[0] as Record<string, unknown>;
  const parts = Object.entries(mapping).map(
    ([col, val]) => `${renderKey(col)} = ${renderExpr(val)}`
  );
  return `do update set ${parts.join(", ")}`;
}

// ============================================================
// Main $sql functor
// ============================================================

function _sql(env: Env, ...args: JseValue[]): JseValue {
  if (args.length === 0) return "";
  const data = args[0];
  if (!Array.isArray(data)) return "";
  if (data.length === 0) return "";

  const parts: string[] = [];
  const pendingValues: unknown[][] = [];

  const flushValues = () => {
    if (pendingValues.length > 0) {
      const rows = pendingValues.map((vlist) =>
        `(${vlist.map(renderExpr).join(", ")})`
      );
      parts.push(`values ${rows.join(", ")}`);
      pendingValues.length = 0;
    }
  };

  for (const item of data) {
    if (!Array.isArray(item) || item.length === 0) continue;
    const kw = item[0];
    if (kw === "$values") {
      pendingValues.push(item.slice(1));
      continue;
    }
    flushValues();
    const rendered = renderClause(item as unknown[]);
    if (rendered) parts.push(rendered);
  }
  flushValues();

  return parts.join("\n");
}

// ============================================================
// Legacy $query / $pattern (backward compatibility)
// ============================================================

export function patternToTriple(
  subject: string,
  predicate: string,
  object: string
): unknown[] {
  const pattern: unknown[] = [];
  if (subject !== "$*" && subject !== "") pattern.push(subject);
  if (predicate !== "$*" && predicate !== "") pattern.push(predicate);
  if (object !== "$*" && object !== "") pattern.push(object);
  return pattern;
}

function patternToTripleForQuery(
  subject: string,
  predicate: string,
  object: string
): unknown[] {
  const pattern: unknown[] = [];
  if (subject === "$*") pattern.push("*");
  else if (subject !== "") pattern.push(subject);
  if (predicate === "$*") pattern.push("*");
  else if (predicate !== "") pattern.push(predicate);
  if (object === "$*") pattern.push("*");
  else if (object !== "") pattern.push(object);
  return pattern;
}

export function tripleToSqlCondition(triple: unknown[]): string {
  const json = JSON.stringify({ triple });
  const spaced = json.replace(/:/g, ": ");
  const escaped = spaced.replace(/'/g, "''");
  return `meta @> '${escaped}'`;
}

export type Functor = (env: Env, ...args: JseValue[]) => JseValue;

export function _pattern(env: Env, ...args: JseValue[]): JseValue {
  if (args.length < 3) throw new Error("$pattern requires (subject, predicate, object)");
  const subj = env.eval(args[0]);
  const pred = env.eval(args[1]);
  const obj = env.eval(args[2]);
  if (typeof subj !== "string" || typeof pred !== "string" || typeof obj !== "string") {
    throw new Error("$pattern requires string arguments");
  }
  const triple = patternToTriple(subj, pred, obj);
  return tripleToSqlCondition(triple);
}

export function _expr(env: Env, ...args: JseValue[]): JseValue {
  if (args.length === 0) return null;
  return env.eval(args[0]);
}

function _and(env: Env, ...args: JseValue[]): JseValue {
  return args.map((e) => env.eval(e)).join(" and ");
}

function _wildcard(_env: Env, ..._args: JseValue[]): JseValue {
  return "*";
}

function _patternForQuery(env: Env, ...args: JseValue[]): JseValue {
  if (args.length < 3) throw new Error("$pattern requires (subject, predicate, object)");
  const subj = env.eval(args[0]);
  const pred = env.eval(args[1]);
  const obj = env.eval(args[2]);
  if (typeof subj !== "string" || typeof pred !== "string" || typeof obj !== "string") {
    throw new Error("$pattern requires string arguments");
  }
  if (subj === "$*" && pred === "$*" && obj === "$*") {
    return tripleToSqlCondition(patternToTriple(subj, pred, obj));
  }
  return tripleToSqlCondition(patternToTripleForQuery(subj, pred, obj));
}

export function _query(env: Env, ...args: JseValue[]): JseValue {
  const local = new Env(env);
  local.load({
    $pattern: _patternForQuery,
    $and: _and,
    "$*": _wildcard,
  });
  const parser = new Parser(local);
  const condition = parser.parse(args) as AstNodeLike;
  const where = condition.apply(local);
  return `select ${QUERY_FIELDS} \nfrom statement \nwhere \n    ${where} \noffset 0\nlimit 100 \n`;
}

export const SQL_FUNCTORS: Record<string, Functor> = {
  $sql: _sql,
  $query: _query,
};
