"""SQL extension functors for JSE.

Migrated from the original engine.py implementation:
- $pattern: Generate SQL for triple pattern matching
- $query: Generate SQL for multi-pattern queries
- $expr: Expression evaluation pass-through
"""

import json
import re
from typing import Callable, TYPE_CHECKING
from pyjse.types import JseValue

QUERY_FIELDS = "subject, predicate, object, meta"

if TYPE_CHECKING:
    from pyjse.env import Env


# Type alias for functors
Functor = Callable[['Env', ...], JseValue]


def pattern_to_triple(subject: str, predicate: str, obj: str) -> list:
    """Convert pattern arguments to triple, excluding '*' wildcards.

    Examples:
        - ["*", "author of", "*"] -> ["author of"]
        - ["Liu Xin", "author of", "*"] -> ["Liu Xin", "author of", "*"]

    Args:
        subject: Subject pattern
        predicate: Predicate pattern
        obj: Object pattern

    Returns:
        List with non-wildcard elements
    """
    pattern = []
    if subject != "*":
        pattern.append(subject)
    if predicate != "*":
        pattern.append(predicate)
    if obj != "*":
        pattern.append(obj)
    return pattern


def triple_to_sql_condition(triple: list) -> str:
    """Build SQL WHERE clause for triple pattern using jsonb containment.

    Args:
        triple: List representing triple pattern

    Returns:
        SQL WHERE condition string
    """
    json_str = json.dumps({"triple": triple})
    escaped = json_str.replace("'", "''")
    return f"meta @> '{escaped}'"


def _pattern(env: 'Env', *args: JseValue) -> JseValue:
    """Generate SQL for triple pattern matching.

    Form: [$pattern, subject, predicate, object]

    Args:
        env: Environment
        *args: (subject, predicate, object) - all must be strings

    Returns:
        SQL query string

    Raises:
        ValueError: If wrong arguments or non-string types
    """
    if len(args) < 3:
        raise ValueError("$pattern requires (subject, predicate, object)")

    subj = env.eval(args[0]) if hasattr(env, 'eval') else args[0]
    pred = env.eval(args[1]) if hasattr(env, 'eval') else args[1]
    obj = env.eval(args[2]) if hasattr(env, 'eval') else args[2]

    if (
        not isinstance(subj, str) or
        not isinstance(pred, str) or
        not isinstance(obj, str)
    ):
        raise ValueError("$pattern requires string arguments")

    triple = pattern_to_triple(subj, pred, obj)
    cond = triple_to_sql_condition(triple)

    return (
        "select \n    subject, predicate, object, meta \n"
        f"from statement as s \nwhere {cond} \noffset 0\nlimit 100 \n"
    )


def _expr(env: 'Env', *args: JseValue) -> JseValue:
    """Expression evaluation pass-through.

    Form: [$expr, expression] or {$expr: expression}
    Evaluates the expression and returns the result.

    Args:
        env: Environment
        *args: Expression to evaluate

    Returns:
        Evaluated expression result
    """
    if not args:
        return None
    return env.eval(args[0]) if hasattr(env, 'eval') else args[0]


def _query(env: 'Env', *args: JseValue) -> JseValue:
    """Generate SQL for multi-pattern query.

    Form: [$query, op, patterns]
    where patterns is a list of SQL strings from $pattern

    Args:
        env: Environment
        *args: (operator, patterns_array)

    Returns:
        Combined SQL query string

    Raises:
        ValueError: If wrong arguments or invalid patterns
    """
    if len(args) < 2:
        raise ValueError("$query expects [op, patterns array]")

    # First arg is operator (currently ignored, assumes "and")
    op = env.eval(args[0]) if hasattr(env, 'eval') else args[0]
    patterns = env.eval(args[1]) if hasattr(env, 'eval') else args[1]

    if not isinstance(patterns, list):
        raise ValueError("$query second argument must be a list")

    conditions = []
    for sql in patterns:
        if not isinstance(sql, str):
            raise ValueError("Pattern must evaluate to SQL string")
        # Extract WHERE clause from SQL
        match = re.search(r"where\s+(.+?)\s+offset", sql, re.IGNORECASE)
        if match:
            conditions.append(f"({match.group(1).strip()})")
        else:
            conditions.append(sql)

    where_clause = " and \n    ".join(conditions)
    return f"select {QUERY_FIELDS} \nfrom statement \nwhere \n    {where_clause} \noffset 0\nlimit 100 \n"


# Dict of all SQL functors for registration
SQL_FUNCTORS: dict[str, Functor] = {
    "$pattern": _pattern,
    "$expr": _expr,
    "$query": _query,
}
