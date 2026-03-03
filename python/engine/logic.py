import pytest
from knowledge.engine.engine import Engine
from knowledge.engine.env import ExpressionEnv

@pytest.fixture
def engine():
    env = ExpressionEnv()
    return Engine(env)

def test_and_basic(engine):
    assert engine.execute(['$and', True, True, True]) is True
    assert engine.execute(['$and', True, False, True]) is False

def test_or_basic(engine):
    assert engine.execute(['$or', False, False, True]) is True
    assert engine.execute(['$or', False, False, False]) is False


def test_not_basic(engine):
    assert engine.execute(['$not', True]) is False
    assert engine.execute(['$not', False]) is True


def test_nested_logic(engine):
    expr = [
            '$or',
            ['$and', True, ['$not', False]],
            ['$and', False, True]
        ]
    assert engine.execute(expr) is True

def test_deep_nesting(engine):
    # $or/$and 将 tail 中每个元素作为独立参数，不要把多个子表达式包在同一个 list 里
    expr = [
        '$not',
        [
            '$or',
            ['$and', False, ['$not', False]],
            ['$not', True]
        ]
    ]
    assert engine.execute(expr) is True

