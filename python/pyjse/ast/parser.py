"""JSON to AST parser for JSE.

Following the design in docs/regular.md:
- Recognizes symbols (strings starting with $ but not $$)
- Identifies expressions in arrays and objects
- Creates AST nodes with proper environment capture
"""

from pyjse.env import Env
from pyjse.types import JseValue
from pyjse.ast.nodes import (
    SymbolNode,
    ArrayNode,
    ObjectNode,
    ObjectExpressionNode,
    QuoteNode,
    LiteralNode,
)


def _is_symbol(s: str) -> bool:
    """Check if string is a JSE symbol.

    Symbols start with $ but not $$.
    Wildcard $* is not a symbol.

    Args:
        s: String to check

    Returns:
        True if string is a symbol
    """
    # Wildcard $* is a literal string, not a symbol
    if s == "$*":
        return False
    return s.startswith("$") and not s.startswith("$$")


def _unescape(s: str) -> str:
    """Unescape $$-prefixed string.

    Args:
        s: String to unescape

    Returns:
        Unescaped string
    """
    if s.startswith("$$"):
        return s[1:]
    return s


class Parser:
    """Parse JSON values into JSE AST nodes.

    The parser identifies expressions based on the formal semantics:
    - ArrayExpr: [symbol, args...] where first element is a symbol
    - ObjectExpr: {symbol: value} where exactly one key is a symbol
    - QuoteExpr: ["$quote", x] or {"$quote": x} (special case)
    """

    def __init__(self, env: Env) -> None:
        """Initialize parser with environment.

        Args:
            env: Environment to pass to constructed AST nodes
        """
        self._env = env

    def parse(self, expr: JseValue) -> JseValue:
        """Parse JSON value into AST node or return primitive.

        Args:
            expr: JSON value to parse

        Returns:
            AST node or primitive value
        """
        # Primitives - return as-is wrapped in LiteralNode
        if expr is None or isinstance(expr, (int, float, bool)):
            return LiteralNode(expr, self._env)

        # Strings - check if symbol
        if isinstance(expr, str):
            if _is_symbol(expr):
                return SymbolNode(expr, self._env)
            return LiteralNode(_unescape(expr), self._env)

        # Arrays - check for expression form
        if isinstance(expr, list):
            return self._parse_list(expr)

        # Objects - check for expression form
        if isinstance(expr, dict):
            return self._parse_dict(expr)

        # Unknown type - wrap as literal
        return LiteralNode(expr, self._env)

    def _parse_list(self, lst: list) -> JseValue:
        """Parse list expression.

        Forms:
        - ["$quote", x] -> QuoteNode
        - [symbol, ...] -> ArrayNode (function call)
        - [...] -> ArrayNode (regular array)

        Args:
            lst: List to parse

        Returns:
            AST node
        """
        if not lst:
            # Empty list
            return ArrayNode([], self._env)

        first = lst[0]

        # Special case: $quote
        if first == "$quote":
            # ["$quote", x] - return x unevaluated
            value = lst[1] if len(lst) > 1 else None
            return QuoteNode(value, self._env)

        # Check if this is a function call form
        if isinstance(first, str) and _is_symbol(first):
            # [symbol, args...] - function call
            elements = [self.parse(e) for e in lst]
            return ArrayNode(elements, self._env)

        # Regular array - evaluate all elements
        elements = [self.parse(e) for e in lst]
        return ArrayNode(elements, self._env)

    def _parse_dict(self, d: dict) -> JseValue:
        """Parse dict expression.

        Forms:
        - {"$quote": x} -> QuoteNode
        - {symbol: value, ...} -> ObjectNode (exactly one symbol key)
        - {...} -> ObjectNode with regular keys

        Args:
            d: Dict to parse

        Returns:
            AST node or dict of parsed values
        """
        # Find symbol keys
        symbol_keys = [k for k in d if _is_symbol(k)]

        if len(symbol_keys) == 0:
            # Regular object - parse all values
            # Note: This creates a dict, not an ObjectNode
            result = {}
            for k, v in d.items():
                parsed_key = _unescape(k) if isinstance(k, str) else k
                parsed_value = self.parse(v)
                # Store the actual parsed value (might be AST node)
                result[parsed_key] = parsed_value
            return ObjectNode(result, self._env)

        if len(symbol_keys) == 1:
            # Operator form: {"$operator": value, "meta": ...}
            operator = symbol_keys[0]

            # Special case: $quote
            if operator == "$quote":
                value = d[operator]
                return QuoteNode(value, self._env)

            # Parse the value
            parsed_value = self.parse(d[operator])

            # Parse metadata (other keys)
            metadata = {}
            for k, v in d.items():
                if k != operator:
                    parsed_key = _unescape(k) if isinstance(k, str) else k
                    parsed_metadata = self.parse(v)
                    metadata[parsed_key] = parsed_metadata

            return ObjectExpressionNode(operator, parsed_value, metadata, self._env)

        # Multiple symbol keys - error per formal semantics
        raise ValueError("JSE structure error: object cannot have multiple operator keys")
