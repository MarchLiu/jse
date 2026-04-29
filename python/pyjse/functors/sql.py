"""SQL generation functors for JSE.

Implements the $sql functor per Issue #3 v4 design:
  {"$sql": [["$keyword", arg...], ...]}

$sql receives raw JSON directly (bypasses JSE parsing for its value),
allowing objects with multiple $keys (e.g. $set, $with values).

Also retains legacy $query / $pattern functors for backward compatibility.
"""

from __future__ import annotations

import json
from typing import Any, Callable, TYPE_CHECKING

from pyjse.types import JseValue
from pyjse.env import Env
from pyjse.ast.parser import Parser
from pyjse.ast.nodes import SymbolNode

if TYPE_CHECKING:
    from pyjse.env import Env

Functor = Callable[['Env', ...], JseValue]
QUERY_FIELDS = "subject, predicate, object, meta"


# ============================================================
# Subquery detection
# ============================================================

def _is_subquery(value: Any) -> bool:
    """Check if a list is a subquery (list of clause arrays)."""
    if not isinstance(value, list) or not value:
        return False
    return all(
        isinstance(item, list) and item
        and isinstance(item[0], str) and item[0].startswith('$')
        for item in value
    )


# ============================================================
# String utilities
# ============================================================

def _is_symbol_str(s: str) -> bool:
    """Check if a raw string is a JSE symbol (starts with $, not $$)."""
    if s == "$*":
        return False
    return s.startswith("$") and not s.startswith("$$")


def _is_escaped_str(s: str) -> bool:
    """Check if a raw string uses $$ escape."""
    return s.startswith("$$")


def _sql_string(s: str) -> str:
    """Escape and quote a string for SQL."""
    escaped = s.replace("'", "''")
    return f"'{escaped}'"


def _is_parenthesized(s: str) -> bool:
    """Check if a string is already fully wrapped in parentheses."""
    if not s.startswith("("):
        return False
    depth = 0
    for i, c in enumerate(s):
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0:
            return i == len(s) - 1
    return False


# ============================================================
# Expression → SQL fragment renderer (raw JSON data)
# ============================================================

def _render_expr(value: Any) -> str:
    """Render any value to a SQL fragment string.

    Works with raw Python types from JSON (not AST nodes).
    """
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)

    if isinstance(value, str):
        if _is_escaped_str(value):
            # $$PROMO-% → '$PROMO-%' (literal $ in SQL string)
            return _sql_string("$" + value[2:])
        if _is_symbol_str(value):
            # $name → name (SQL identifier)
            return value[1:]
        # Plain string → SQL string literal
        return _sql_string(value)

    if isinstance(value, dict):
        return _render_dict_expr(value)

    if isinstance(value, list):
        if not value:
            return ""
        # Check if subquery
        if _is_subquery(value):
            return _render_subquery(value)
        # Check if expression (starts with $)
        first = value[0]
        if isinstance(first, str) and first.startswith("$") and not first.startswith("$$"):
            return _render_list_expr(value)
        # Plain list → comma-separated
        return ", ".join(_render_expr(v) for v in value)

    return str(value)


# ============================================================
# Dict / list expression renderers
# ============================================================

def _render_dict_expr(d: dict) -> str:
    """Render a dict-form expression."""
    if not d:
        return ""

    # Find $ operator keys
    op_keys = [k for k in d if isinstance(k, str) and _is_symbol_str(k)]
    if not op_keys:
        # Plain data dict → render as key=value pairs
        return ", ".join(f"{_render_key(k)} = {_render_expr(v)}" for k, v in d.items())
    if len(op_keys) > 1:
        # Multiple $ keys — treat as data dict (e.g. $set mapping)
        return ", ".join(f"{_render_key(k)} = {_render_expr(v)}" for k, v in d.items())

    op = op_keys[0]

    if op == "$symbol":
        return f'"{d[op]}"'

    # Generic: render value with the operator
    val = d[op]
    return _render_expr(val)


def _render_key(k: Any) -> str:
    """Render a dict key as a SQL identifier."""
    if isinstance(k, str):
        if k.startswith("$") and not k.startswith("$$"):
            return k[1:]
        if k.startswith("$$"):
            return "$" + k[2:]
        return k
    return str(k)


def _render_list_expr(lst: list) -> str:
    """Render a list expression [op, arg...]."""
    if not lst:
        return ""
    op = lst[0]
    if not isinstance(op, str):
        return ", ".join(_render_expr(v) for v in lst)

    if op.startswith("$$"):
        return ", ".join(_render_expr(v) for v in lst)

    args = lst[1:]
    return _render_func(op, args)


# ============================================================
# Function call dispatch
# ============================================================

def _render_func(op: str, args: list) -> str:
    """Render a function call by operator name."""
    handlers: dict[str, Callable[[list], str]] = {
        # Aliases
        "$as": _as_handler,
        # Aggregates
        "$count": _count_handler,
        "$sum": _agg_handler("sum"),
        "$avg": _agg_handler("avg"),
        "$max": _agg_handler("max"),
        "$min": _agg_handler("min"),
        # Comparisons
        "$eq": _binop_handler("="),
        "$ne": _binop_handler("!="),
        "$gt": _binop_handler(">"),
        "$gte": _binop_handler(">="),
        "$lt": _binop_handler("<"),
        "$lte": _binop_handler("<="),
        "$like": _binop_handler("like"),
        "$is": _is_handler,
        "$is-not": _is_not_handler,
        # Logical
        "$and": _logical_handler("and"),
        "$or": _logical_handler("or"),
        # Special
        "$in": _in_handler,
        "$case": _case_handler,
        "$excluded": _excluded_handler,
    }

    handler = handlers.get(op)
    if handler:
        return handler(args)

    # Unknown → generic function call
    op_name = op[1:]  # strip $
    rendered_args = ", ".join(_render_expr(a) for a in args)
    return f"{op_name}({rendered_args})"


def _as_handler(args: list) -> str:
    """Render $as: Symbol → x as y, Array → (expr) as y, String → 's' as y."""
    if len(args) < 2:
        return ""
    expr = args[0]
    alias = _render_expr(args[1])

    if isinstance(expr, list):
        return f"({_render_expr(expr)}) as {alias}"
    if isinstance(expr, str) and _is_symbol_str(expr):
        return f"{expr[1:]} as {alias}"
    return f"{_render_expr(expr)} as {alias}"


def _count_handler(args: list) -> str:
    """Render $count. $* → *."""
    if not args:
        return "count(*)"
    arg = args[0]
    if isinstance(arg, str) and arg == "$*":
        return "count(*)"
    return f"count({_render_expr(arg)})"


def _agg_handler(fn: str) -> Callable[[list], str]:
    """Make a handler for aggregate functions."""
    def handler(args: list) -> str:
        if not args:
            return f"{fn}(*)"
        return f"{fn}({_render_expr(args[0])})"
    return handler


def _binop_handler(op: str) -> Callable[[list], str]:
    """Make a handler for binary operators."""
    def handler(args: list) -> str:
        if len(args) < 2:
            if args:
                return _render_expr(args[0])
            return ""
        return f"{_render_expr(args[0])} {op} {_render_expr(args[1])}"
    return handler


def _is_handler(args: list) -> str:
    """Render $is. Handles null specially."""
    if len(args) < 2:
        return ""
    left = _render_expr(args[0])
    if args[1] is None:
        return f"{left} is null"
    return f"{left} is {_render_expr(args[1])}"


def _is_not_handler(args: list) -> str:
    """Render $is-not. Handles null specially."""
    if len(args) < 2:
        return ""
    left = _render_expr(args[0])
    if args[1] is None:
        return f"{left} is not null"
    return f"{left} is not {_render_expr(args[1])}"


def _logical_handler(op: str) -> Callable[[list], str]:
    """Render $and/$or with proper parenthesization.

    Per issue #3: [$and, exp1, exp2] → ((exp1) and (exp2))
    Each operand is individually parenthesized, then the whole thing wrapped.
    """
    def handler(args: list) -> str:
        if not args:
            return "true" if op == "and" else "false"
        rendered = [_render_expr(a) for a in args]
        # Wrap each arg in parens, unless already wrapped by nested $and/$or
        parts = [f"({r})" if not _is_parenthesized(r) else r for r in rendered]
        sep = f" {op} "
        return f"({sep.join(parts)})"
    return handler


def _in_handler(args: list) -> str:
    """Render $in. Handles subquery values."""
    if len(args) < 2:
        return ""
    col = _render_expr(args[0])
    val = args[1]

    if isinstance(val, list) and _is_subquery(val):
        inner = _render_subquery(val)
        return f"{col} in ({inner})"

    if isinstance(val, list):
        vals = ", ".join(_render_expr(v) for v in val)
        return f"{col} in ({vals})"

    return f"{col} in ({_render_expr(val)})"


def _case_handler(args: list) -> str:
    """Render $case expression."""
    parts = ["case"]
    else_val = None

    for arg in args:
        if isinstance(arg, list) and arg and isinstance(arg[0], str):
            if arg[0] == "$when" and len(arg) >= 3:
                cond = _render_expr(arg[1])
                then = _render_expr(arg[2])
                parts.append(f"when {cond} then {then}")
            elif arg[0] == "$else" and len(arg) >= 2:
                else_val = _render_expr(arg[1])

    if else_val is not None:
        parts.append(f"else {else_val}")
    parts.append("end")
    return " ".join(parts)


def _excluded_handler(args: list) -> str:
    """Render $excluded (for UPSERT)."""
    if not args:
        return "excluded"
    col = _render_expr(args[0])
    return f"excluded.{col}"


# ============================================================
# Subquery rendering
# ============================================================

def _render_subquery(clauses: list) -> str:
    """Render a subquery (list of clause arrays) as SQL."""
    parts = [_render_clause(c) for c in clauses if c]
    return " ".join(parts)


# ============================================================
# Clause → SQL fragment renderer
# ============================================================

def _render_clause(clause: list) -> str:
    """Render a single clause [keyword, arg...] to a SQL fragment."""
    if not clause:
        return ""

    kw = clause[0]
    if not isinstance(kw, str) or not kw.startswith("$"):
        return ""

    args = clause[1:]

    # --- Query clauses ---

    if kw == "$select":
        cols = ", ".join(_render_expr(a) for a in args)
        return f"select {cols}"

    if kw == "$from":
        return f"from {_render_table(args)}"

    if kw == "$join":
        return f"join {_render_join(args)}"

    if kw == "$left-join":
        return f"left join {_render_join(args)}"

    if kw == "$right-join":
        return f"right join {_render_join(args)}"

    if kw == "$full-join":
        return f"full join {_render_join(args)}"

    if kw == "$cross-join":
        return f"cross join {_render_table(args)}"

    if kw == "$where":
        return f"where {_render_expr(args[0]) if args else ''}"

    if kw == "$group-by":
        return f"group by {_render_expr(args[0]) if args else ''}"

    if kw == "$having":
        return f"having {_render_expr(args[0]) if args else ''}"

    if kw == "$order-by":
        return _render_order_by(args)

    if kw == "$limit":
        return f"limit {_render_expr(args[0])}" if args else ""

    if kw == "$offset":
        return f"offset {_render_expr(args[0])}" if args else ""

    if kw == "$with":
        return _render_with(args)

    # --- DML clauses ---

    if kw == "$insert-into":
        return _render_insert_into(args)

    if kw == "$values":
        vals = ", ".join(_render_expr(a) for a in args)
        return f"values ({vals})"

    if kw == "$update":
        return f"update {_render_table(args)}"

    if kw == "$set":
        return _render_set(args)

    if kw == "$delete-from":
        return f"delete from {_render_table(args)}"

    if kw == "$on-conflict":
        col = _render_expr(args[0]) if args else ""
        return f"on conflict ({col})"

    if kw == "$do-update":
        return _render_do_update(args)

    # Unknown clause
    return kw[1:]


# ============================================================
# Clause helper renderers
# ============================================================

def _render_table(args: list) -> str:
    """Render table reference (may include $as)."""
    if not args:
        return ""
    first = args[0]
    if isinstance(first, list) and first and isinstance(first[0], str) and first[0] == "$as":
        return _render_list_expr(first)
    return _render_expr(first)


def _render_join(args: list) -> str:
    """Render JOIN: table_reference + condition."""
    if not args:
        return ""
    table = _render_expr(args[0])
    if len(args) >= 2:
        cond = _render_expr(args[1])
        return f"{table} on {cond}"
    return table


def _render_order_by(args: list) -> str:
    """Render ORDER BY clause."""
    if not args:
        return ""
    col = _render_expr(args[0])
    if len(args) >= 2:
        direction = args[1]
        if isinstance(direction, str) and _is_symbol_str(direction):
            dir_str = direction[1:]
            if dir_str in ("desc", "asc"):
                return f"order by {col} {dir_str}"
        return f"order by {col} {_render_expr(direction)}"
    return f"order by {col}"


def _render_with(args: list) -> str:
    """Render WITH (CTE) clause.

    $with value format: {$cte_name: [[clause...], ...], ...}
    CTE name keys may have $ prefix (CTE names are SQL identifiers).
    """
    if not args or not isinstance(args[0], dict):
        return ""

    cte_defs = args[0]
    cte_parts = []

    for cte_name_key, cte_clauses in cte_defs.items():
        if isinstance(cte_name_key, str):
            # Strip $ prefix if present (CTE name as identifier)
            cte_name = cte_name_key[1:] if _is_symbol_str(cte_name_key) else cte_name_key
        else:
            cte_name = str(cte_name_key)

        if isinstance(cte_clauses, list) and cte_clauses:
            inner_sql = " ".join(_render_clause(c) for c in cte_clauses)
            cte_parts.append(f"{cte_name} as ({inner_sql})")

    if not cte_parts:
        return ""

    return "with " + ",\n".join(cte_parts)


def _render_insert_into(args: list) -> str:
    """Render INSERT INTO clause."""
    if not args:
        return "insert into"
    table = _render_expr(args[0])
    if len(args) > 1:
        cols = ", ".join(_render_expr(a) for a in args[1:])
        return f"insert into {table} ({cols})"
    return f"insert into {table}"


def _render_set(args: list) -> str:
    """Render SET clause from a {$col: expr, ...} mapping."""
    if not args or not isinstance(args[0], dict):
        return ""
    mapping = args[0]
    parts = []
    for col, val in mapping.items():
        col_str = _render_key(col)
        parts.append(f"{col_str} = {_render_expr(val)}")
    return "set " + ", ".join(parts)


def _render_do_update(args: list) -> str:
    """Render DO UPDATE SET for UPSERT."""
    if not args or not isinstance(args[0], dict):
        return ""
    mapping = args[0]
    parts = []
    for col, val in mapping.items():
        col_str = _render_key(col)
        parts.append(f"{col_str} = {_render_expr(val)}")
    return "do update set " + ", ".join(parts)


# ============================================================
# Main $sql functor
# ============================================================

def _sql(env: 'Env', *args: JseValue) -> JseValue:
    """Generate SQL from JSE structural expressions.

    Receives raw JSON data (list of clause arrays) directly.

    Usage:
        {"$sql": [["$select", "$name"], ["$from", "$users"], ...]}

    Per Issue #3 v4 design.
    """
    if not args:
        return ""

    data = args[0]  # Raw JSON: list of clause arrays

    if not isinstance(data, list):
        return ""

    if not data:
        return ""

    # Combine consecutive $values clauses into single VALUES tuple list
    parts: list[str] = []
    pending_values: list[list] = []

    def flush_values() -> None:
        if pending_values:
            all_vals = ", ".join(
                f"({', '.join(_render_expr(v) for v in vlist)})"
                for vlist in pending_values
            )
            parts.append(f"values {all_vals}")
            pending_values.clear()

    for clause in data:
        if not isinstance(clause, list) or not clause:
            continue
        kw = clause[0]
        if kw == "$values":
            pending_values.append(clause[1:])
            continue
        flush_values()
        rendered = _render_clause(clause)
        if rendered:
            parts.append(rendered)

    flush_values()

    return "\n".join(parts)


# ============================================================
# Legacy $query / $pattern functors (backward compatibility)
# ============================================================

class PatternNode(SymbolNode):
    """Pattern node for legacy SQL query functor."""
    def __init__(self, name: str, env: 'Env') -> None:
        super().__init__(name, env)
        self._name = name
        self._env = env


def pattern_to_triple(subject: str, predicate: str, object: str) -> list[str]:
    """Generate triple for a pattern (legacy)."""
    return [subject, predicate, object]


def triple_to_sql_condition(triple: list[str]) -> str:
    """Generate SQL condition for a triple pattern (legacy)."""
    return "meta @> '" + json.dumps({"triple": triple}) + "'"


def _pattern(env: 'Env', *args: JseValue) -> JseValue:
    """Generate SQL for triple pattern matching (legacy)."""
    if len(args) < 3:
        raise ValueError("$pattern requires (subject, predicate, object)")

    subj = env.eval(args[0]) if hasattr(env, 'eval') else args[0]
    pred = env.eval(args[1]) if hasattr(env, 'eval') else args[1]
    obj = env.eval(args[2]) if hasattr(env, 'eval') else args[2]

    if all(x == "*" for x in (subj, pred, obj)):
        raise ValueError("subject, predicate, and object must not be all '*'")

    triple = pattern_to_triple(str(subj), str(pred), str(obj))
    cond = triple_to_sql_condition(triple)

    return (
        "select \n    subject, predicate, object, meta \n"
        f"from statement as s \nwhere {cond} \noffset 0\nlimit 100 \n"
    )


def _legacy_and(env: 'Env', *args: JseValue) -> JseValue:
    """SQL AND for legacy $query (joins WHERE conditions)."""
    tokens = [str(env.eval(e)) for e in args]
    return " and ".join(tokens)


def _wildcard(env: 'Env', *args: JseValue) -> JseValue:
    """Wildcard for legacy $pattern."""
    return "*"


def _query(env: 'Env', *args: JseValue) -> JseValue:
    """Generate SQL for multi-pattern query (legacy)."""
    local = Env(env)
    local.load({
        "$pattern": _pattern,
        "$and": _legacy_and,
        "$*": _wildcard,
    })
    parser = Parser(local)
    condition = parser.parse(args)
    where = condition.apply(local)

    sql = f"select {QUERY_FIELDS} \nfrom statement \nwhere \n    {where} \n"
    return sql


# Dict of all SQL functors for registration
SQL_FUNCTORS: dict[str, Functor] = {
    "$sql": _sql,
    "$query": _query,
}
