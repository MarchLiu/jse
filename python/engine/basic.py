import pytest
from knowledge.engine.engine import Engine
from knowledge.engine.env import ExpressionEnv

@pytest.fixture
def engine():
    env = ExpressionEnv()
    # env可进一步挂载知识和语句数据，但此处只测基础表达式
    return Engine(env)

def test_number_expr(engine):
    expr = 42
    result = engine.execute(expr)
    assert result == 42

def test_float_expr(engine):
    expr = 3.14
    result = engine.execute(expr)
    assert result == 3.14

def test_string_expr(engine):
    expr = "hello"
    result = engine.execute(expr)
    assert result == "hello"

def test_boolean_expr(engine):
    assert engine.execute(True) is True
    assert engine.execute(False) is False

def test_null_expr(engine):
    expr = None
    result = engine.execute(expr)
    assert result is None

def test_array_expr(engine):
    expr = [1, 2, 3]
    result = engine.execute(expr)
    # ListAST应返回子节点列表
    assert isinstance(result, list)
    assert result == [1, 2, 3]

def test_dict_expr(engine):
    expr = {"a": 1, "b": "x"}
    result = engine.execute(expr)
    # DictAST应返回dict
    assert isinstance(result, dict)
    assert result == {"a": 1, "b": "x"}


if __name__ == "__main__":
    pytest.main()