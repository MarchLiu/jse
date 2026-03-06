"""Concrete AST node implementations for JSE.

Following the design in docs/regular.md:
- SymbolNode: Represents a symbol reference like $x
- ArrayNode: Represents [operator, args...] function call
- ObjectNode: Represents {"$operator": value} operator call
- QuoteNode: Represents quoted (unevaluated) expression
- LambdaNode: Represents lambda function with closure
"""

from typing import Any, TYPE_CHECKING
from pyjse.ast.base import AstNode
from pyjse.types import JseValue

if TYPE_CHECKING:
    from pyjse.env import Env


class SymbolNode(AstNode):
    """Represents a symbol reference like $x.

    When applied, looks up the symbol in the call-time environment.
    """

    def __init__(self, name: str, env: 'Env') -> None:
        """Initialize symbol node.

        Args:
            name: Symbol name (e.g., "$x")
            env: Construct-time environment
        """
        super().__init__(env)
        self._name = name

    def apply(self, env: 'Env') -> JseValue:
        """Look up symbol in call-time environment.

        Args:
            env: Call-time environment for lookup

        Returns:
            The bound value

        Raises:
            NameError: If symbol is not found
        """
        value = env.resolve(self._name)
        if value is None:
            raise NameError(f"Symbol '{self._name}' not found")
        return value


class ArrayNode(AstNode):
    """Represents an array expression.

    Can be either:
    - A function call: [operator, args...]
    - A regular array: [elements...]
    """

    def __init__(self, elements: list[JseValue], env: 'Env') -> None:
        """Initialize array node.

        Args:
            elements: List of elements (may include AST nodes)
            env: Construct-time environment
        """
        super().__init__(env)
        self._elements = elements

    def apply(self, env: 'Env') -> JseValue:
        """Evaluate array node.

        If first element is a SymbolNode, treats as function call.
        Otherwise evaluates all elements.

        Args:
            env: Call-time environment

        Returns:
            Function call result or evaluated array
        """
        if not self._elements:
            return []

        first = self._elements[0]

        # Check if this is a function call form
        if isinstance(first, SymbolNode):
            # Look up the functor
            functor = env.resolve(first._name)
            if functor is None:
                raise NameError(f"Unknown operator: {first._name}")

            # Special forms: don't evaluate all arguments
            # $def, $defn, $lambda need unevaluated symbols/expressions
            special_forms = ('$def', '$defn', '$lambda', '$quote')
            if first._name in special_forms:
                # Pass arguments unevaluated (functor will handle)
                if callable(functor):
                    return functor(env, *self._elements[1:])
                return functor

            # Regular functors: evaluate arguments first
            evaluated_args = [env.eval(arg) for arg in self._elements[1:]]

            # Call the functor
            if callable(functor):
                return functor(env, *evaluated_args)
            return functor

        # Regular array - evaluate all elements
        return [env.eval(elem) for elem in self._elements]


class ObjectNode(AstNode):
    """Represents an object with key-value pairs.

    Form: {key: value, ...}
    """
    def __init__(self, dict: dict[str, JseValue], env: 'Env') -> None:
        """Initialize object node.
        """
        super().__init__(env)
        self._dict = dict
        
    def apply(self, env: 'Env') -> JseValue:
        """Evaluate object node.
        """
        return {k: env.eval(v) for k, v in self._dict.items()}


class ObjectExpressionNode(AstNode):
    """Represents an object expression with operator key.

    Form: {"$operator": value, "meta": ...}
    """

    def __init__(
        self,
        operator: str,
        value: JseValue,
        metadata: dict[str, JseValue],
        env: 'Env'
    ) -> None:
        """Initialize object node.

        Args:
            operator: The operator symbol (e.g., "$add")
            value: The operand value
            metadata: Additional metadata keys
            env: Construct-time environment
        """
        super().__init__(env)
        self._operator = operator
        self._value = value
        self._metadata = metadata

    def apply(self, env: 'Env') -> JseValue:
        """Evaluate object node as operator call.

        Args:
            env: Call-time environment

        Returns:
            Operator result
        """
        # Look up the functor
        functor = env.resolve(self._operator)
        if functor is None:
            raise NameError(f"Unknown operator: {self._operator}")

        # For object expressions, we need to evaluate the value as arguments
        # If the value is an ArrayNode, we want to evaluate its elements as data,
        # NOT as a function call (which ArrayNode.apply() would do)
        from .nodes import ArrayNode

        if self._operator == "$expr":
            # $expr evaluates the whole expression and returns the result
            args = [env.eval(self._value)]
        elif isinstance(self._value, ArrayNode):
            # Get the elements of the array node
            elements = self._value._elements
            # Evaluate each element as data (not as function calls)
            args = [_deep_eval(env, elem) for elem in elements]
        else:
            # For other types, just evaluate normally
            args = [env.eval(self._value)]

        # Call the functor
        if callable(functor):
            return functor(env, *args)
        return functor


def _deep_eval(env: 'Env', value: JseValue) -> JseValue:
    """Deep evaluate a value, handling nested arrays and AST nodes.

    Args:
        env: Environment for evaluation
        value: Value to evaluate

    Returns:
        Evaluated value
    """
    # First, evaluate any AST node
    evaluated = env.eval(value)

    # If result is an array, recursively evaluate its elements
    if isinstance(evaluated, list):
        return [_deep_eval(env, item) for item in evaluated]

    # If result is a plain object (not AST node), evaluate its values
    if isinstance(evaluated, dict):
        result = {}
        for k, v in evaluated.items():
            result[k] = _deep_eval(env, v)
        return result

    return evaluated


class QuoteNode(AstNode):
    """Represents a quoted (unevaluated) expression.

    Form: ["$quote", expr] or {"$quote": expr}
    Returns the expression without evaluation.
    """

    def __init__(self, value: JseValue, env: 'Env') -> None:
        """Initialize quote node.

        Args:
            value: The quoted expression (returned as-is)
            env: Construct-time environment
        """
        super().__init__(env)
        self._value = value

    def apply(self, env: 'Env') -> JseValue:
        """Return quoted value without evaluation.

        Args:
            env: Call-time environment (ignored)

        Returns:
            The quoted value as-is
        """
        return self._value


class LambdaNode(AstNode):
    """Represents a lambda function with closure.

    Captures construct-time environment for static scoping.
    When applied, creates new environment with closure as parent.
    """

    def __init__(
        self,
        params: list[str],
        body: JseValue,
        closure_env: 'Env'
    ) -> None:
        """Initialize lambda node.

        Args:
            params: Parameter names (e.g., ["$x", "$y"])
            body: Function body expression
            closure_env: Environment to capture (construct-time)
        """
        super().__init__(closure_env)
        self._params = params
        self._body = body
        self._closure_env = closure_env

    def apply(self, env: 'Env', *args: JseValue) -> JseValue:
        """Apply lambda with arguments.

        Creates new environment with closure as parent (static scoping).

        Args:
            env: Call-time environment
            *args: Argument values to bind to parameters

        Returns:
            Result of evaluating body

        Raises:
            ValueError: If argument count doesn't match parameter count
        """
        if len(args) != len(self._params):
            raise ValueError(
                f"Lambda expects {len(self._params)} args, got {len(args)}"
            )

        # Create new environment for this call
        # Parent is closure_env (static scoping!)
        from pyjse.env import Env
        call_env = Env(parent=self._closure_env)

        # Bind parameters to arguments
        for param, arg in zip(self._params, args):
            call_env.set(param, arg)

        # Evaluate body in call environment
        return call_env.eval(self._body)


class LiteralNode(AstNode):
    """Represents a literal value (number, string, bool, null).

    Returns itself when applied (no evaluation needed).
    """

    def __init__(self, value: JseValue, env: 'Env') -> None:
        """Initialize literal node.

        Args:
            value: The literal value
            env: Construct-time environment
        """
        super().__init__(env)
        self._value = value

    def apply(self, env: 'Env') -> JseValue:
        """Return literal value.

        Args:
            env: Call-time environment (ignored)

        Returns:
            The literal value
        """
        return self._value
