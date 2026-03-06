from pyjse import Engine, Env
from pyjse.functors.utils import UTILS_FUNCTORS
from pyjse.functors.sql import SQL_FUNCTORS, QUERY_FIELDS
import pytest


@pytest.fixture
def engine():
    env = Env()
    env.load(UTILS_FUNCTORS)
    env.load(SQL_FUNCTORS)
    engine = Engine(env)
    return engine


def test_basic_query(engine):
    query = {
        "$expr": ["$pattern", "$*", "author of", "$*"],
    }

    result = engine.execute(query)

    assert "select" in result
    assert "subject, predicate, object, meta" in result
    assert "from statement as s" in result
    assert "author of" in result
    assert "triple" in result
    assert "offset 0" in result
    assert "limit 100" in result


def test_combined_query(engine):
    query = {
        "$query": [
            "$and",
            [
                ["$pattern", "Liu Xin", "author of", "$*"],
                ["$pattern", "$*", "author of", "$*"],
            ],
        ],
    }

    result = engine.execute(query)

    assert f"select {QUERY_FIELDS}" in result
    assert "from statement" in result
    assert "Liu Xin" in result
    assert "author of" in result
    assert " and " in result
    assert "offset 0" in result
    assert "limit 100" in result
