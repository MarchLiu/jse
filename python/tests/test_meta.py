"""Tests for meta mechanism in JSE.

Meta mechanism allows passing additional metadata to functors through the
environment. When an expression like {"$operator": value, "meta_key": meta_value}
is evaluated, the metadata is set in the environment before the functor is called,
and cleared after the functor returns.
"""

import pytest
from pyjse import Engine, ExpressionEnv
from pyjse.ast.base import AstNode


def _eval_meta_value(env, value):
    """Evaluate a metadata value if it's an AST node."""
    if isinstance(value, AstNode):
        return env.eval(value)
    return value


# A functor that returns the current metadata from the environment
def _get_meta(env, *args):
    """Return the current metadata context with evaluated values."""
    meta = env.get_meta()
    # Evaluate all meta values
    return {k: _eval_meta_value(env, v) for k, v in meta.items()}


# A functor that returns a specific key from metadata
def _get_meta_key(env, *args):
    """Return a specific key from metadata."""
    if not args:
        return None
    key = args[0]
    meta = env.get_meta()
    if meta is None:
        return None
    value = meta.get(key)
    return _eval_meta_value(env, value)


# A functor that returns all metadata plus arguments
def _meta_with_args(env, *args):
    """Return dict with metadata and evaluated arguments."""
    meta = env.get_meta()
    result = {
        "meta": {},
        "args": list(args)
    }
    for k, v in meta.items():
        result["meta"][k] = _eval_meta_value(env, v)
    return result


# A functor that stores meta and returns the argument unchanged
def _identity_with_meta(env, *args):
    """Return first arg, but verify meta is accessible."""
    meta = env.get_meta()
    # Store meta in a side effect (for testing purposes)
    _identity_with_meta.last_meta = {k: _eval_meta_value(env, v) for k, v in meta.items()}
    if args:
        return _eval_meta_value(env, args[0])
    return None


@pytest.fixture
def engine_with_meta_functors():
    """Create engine with meta-related functors."""
    env = ExpressionEnv()
    env.register("$get_meta", _get_meta)
    env.register("$get_meta_key", _get_meta_key)
    env.register("$meta_with_args", _meta_with_args)
    env.register("$identity", _identity_with_meta)
    return Engine(env)


def test_basic_meta_passing(engine_with_meta_functors):
    """Test that basic metadata is passed to functor."""
    # Expression with metadata
    expr = {
        "$get_meta": None,
        "key1": "value1",
        "key2": 42
    }
    result = engine_with_meta_functors.execute(expr)

    assert isinstance(result, dict)
    assert "key1" in result
    assert "key2" in result


def test_meta_string_value(engine_with_meta_functors):
    """Test that string metadata values are passed correctly."""
    expr = {
        "$get_meta_key": "name",
        "name": "test_value"
    }
    result = engine_with_meta_functors.execute(expr)
    assert result == "test_value"


def test_meta_number_value(engine_with_meta_functors):
    """Test that numeric metadata values are passed correctly."""
    expr = {
        "$get_meta_key": "count",
        "count": 123
    }
    result = engine_with_meta_functors.execute(expr)
    assert result == 123


def test_meta_with_multiple_keys(engine_with_meta_functors):
    """Test multiple metadata keys."""
    expr = {
        "$get_meta": None,
        "first": "one",
        "second": "two",
        "third": 3
    }
    result = engine_with_meta_functors.execute(expr)

    assert result["first"] == "one"
    assert result["second"] == "two"
    assert result["third"] == 3


def test_meta_with_args(engine_with_meta_functors):
    """Test that both metadata and arguments are available."""
    expr = {
        "$meta_with_args": ["arg1", "arg2"],
        "meta_key": "meta_value"
    }
    result = engine_with_meta_functors.execute(expr)

    assert isinstance(result, dict)
    assert "meta" in result
    assert "args" in result
    assert result["meta"]["meta_key"] == "meta_value"


def test_meta_cleared_after_functor(engine_with_meta_functors):
    """Test that metadata is cleared after functor returns."""
    # First call with metadata
    expr1 = {
        "$get_meta": None,
        "temp_key": "temp_value"
    }
    result1 = engine_with_meta_functors.execute(expr1)
    assert "temp_key" in result1

    # Second call without metadata - should return empty dict
    expr2 = {"$get_meta": None}
    result2 = engine_with_meta_functors.execute(expr2)
    assert result2 == {}


def test_meta_with_object_value(engine_with_meta_functors):
    """Test metadata with object values."""
    expr = {
        "$get_meta_key": "config",
        "config": {"nested": "value", "number": 42}
    }
    result = engine_with_meta_functors.execute(expr)
    assert result == {"nested": "value", "number": 42}


def test_meta_with_list_value(engine_with_meta_functors):
    """Test metadata with list values."""
    expr = {
        "$get_meta_key": "items",
        "items": [1, 2, 3]
    }
    result = engine_with_meta_functors.execute(expr)
    assert result == [1, 2, 3]


def test_meta_null_value(engine_with_meta_functors):
    """Test metadata with null value."""
    expr = {
        "$get_meta_key": "nullable",
        "nullable": None
    }
    result = engine_with_meta_functors.execute(expr)
    assert result is None


def test_meta_boolean_value(engine_with_meta_functors):
    """Test metadata with boolean values."""
    expr = {
        "$get_meta_key": "flag",
        "flag": True
    }
    result = engine_with_meta_functors.execute(expr)
    assert result is True

    expr2 = {
        "$get_meta_key": "flag",
        "flag": False
    }
    result2 = engine_with_meta_functors.execute(expr2)
    assert result2 is False


def test_meta_missing_key(engine_with_meta_functors):
    """Test accessing missing metadata key."""
    expr = {
        "$get_meta_key": "nonexistent"
    }
    result = engine_with_meta_functors.execute(expr)
    assert result is None


def test_meta_available_during_functor_execution(engine_with_meta_functors):
    """Test that meta is available during functor execution and cleared after."""
    # Call a functor that stores meta in a side effect
    expr = {
        "$identity": "return_value",
        "stored_key": "stored_value"
    }
    result = engine_with_meta_functors.execute(expr)

    # The result should be the argument
    assert result == "return_value"

    # But the functor should have captured the meta
    assert hasattr(_identity_with_meta, 'last_meta')
    assert _identity_with_meta.last_meta["stored_key"] == "stored_value"


def test_meta_with_nested_list_value(engine_with_meta_functors):
    """Test metadata with nested list values."""
    expr = {
        "$get_meta_key": "nested",
        "nested": [[1, 2], [3, 4]]
    }
    result = engine_with_meta_functors.execute(expr)
    assert result == [[1, 2], [3, 4]]


def test_meta_with_complex_object(engine_with_meta_functors):
    """Test metadata with complex nested object."""
    expr = {
        "$get_meta_key": "complex",
        "complex": {
            "level1": {
                "level2": "deep_value"
            },
            "array": [1, 2, 3]
        }
    }
    result = engine_with_meta_functors.execute(expr)
    assert result["level1"]["level2"] == "deep_value"
    assert result["array"] == [1, 2, 3]
