from knowledge.engine.engine import Engine
from knowledge.engine.env import Env
from knowledge.engine.sql import QUERY_FIELDS


def test_basic_query():
    query = {
        "$expr": ["$pattern", "$*", "author of", "$*"]
    }

    sql = """
select 
    subject, predicate, object, meta 
from statement as s 
where meta @> '{{triple: ["author of"]}}' 
offset 0
limit 100 
"""

    env = Env()
    engine = Engine(env)
    result = engine.execute(query)
    assert result == sql
    

def test_combined_query():
    query = {
        "$query": [
            "$and", [
                ["$pattern", "Liu Xin", "author of", "$*"],
                ["$pattern", "$*", "author of", "$*"],
            ]
        ]
    }
    sql = f"""
select {QUERY_FIELDS} 
from statement 
where 
    (meta @> '{{triple: ["Liu Xin", "author of", "$*"]}}') and 
    (meta @> '{{triple: ["author of"]}}') 
offset 0
limit 100 
"""
    env = Env()
    engine = Engine(env)
    result = engine.execute(query)
    assert result == sql