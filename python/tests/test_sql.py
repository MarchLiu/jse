"""Tests for the $sql functor — Issue #3 v4 design.

Covers all 12 cases from the issue plus extra scenarios:
- Nested AND/OR, JOINs, CTEs, subqueries
- GROUP BY, aggregates, HAVING, ORDER BY, LIMIT
- INSERT (single, multi-row, UPSERT), UPDATE, DELETE
- $symbol quoted identifiers, $$ escape, null/boolean
- CASE WHEN, CROSS JOIN, multi-table JOIN
"""

import pytest
from pyjse import Engine, Env, SQL_FUNCTORS


@pytest.fixture
def engine():
    env = Env()
    env.load(SQL_FUNCTORS)
    return Engine(env)


def _ex(engine, expr):
    return engine.execute(expr)


# ============================================================
# Case 1: Nested AND/OR
# ============================================================

def test_nested_and_or(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$name", "$age"],
        ["$from", "$users"],
        ["$where", ["$and",
            ["$gt", "$age", 18],
            ["$or",
                ["$eq", "$status", "active"],
                ["$eq", "$role", "admin"]
            ]
        ]]
    ]})
    assert "select name, age" in result
    assert "from users" in result
    assert "age > 18" in result
    assert "status = 'active'" in result
    assert "role = 'admin'" in result
    assert result.count(" and ") == 1
    assert result.count(" or ") == 1


# ============================================================
# Case 2: JOIN with alias and ON
# ============================================================

def test_join_with_alias(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$u.name", "$o.total"],
        ["$from", ["$as", "$users", "$u"]],
        ["$join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
        ["$where", ["$gt", "$o.total", 100]]
    ]})
    assert "select u.name, o.total" in result
    assert "from users as u" in result
    assert "join orders as o on u.id = o.user_id" in result
    assert "where o.total > 100" in result


# ============================================================
# Case 3: LEFT JOIN + NULL
# ============================================================

def test_left_join_null(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$u.name", "$o.total"],
        ["$from", ["$as", "$users", "$u"]],
        ["$left-join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
        ["$where", ["$is", "$o.total", None]]
    ]})
    assert "left join" in result
    assert "o.total is null" in result


def test_right_join(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$a.x"],
        ["$from", ["$as", "$t1", "$a"]],
        ["$right-join", ["$as", "$t2", "$b"], ["$eq", "$a.id", "$b.id"]]
    ]})
    assert "right join" in result


def test_full_join(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$a.x"],
        ["$from", ["$as", "$t1", "$a"]],
        ["$full-join", ["$as", "$t2", "$b"], ["$eq", "$a.id", "$b.id"]]
    ]})
    assert "full join" in result


# ============================================================
# Case 4: CTE (WITH)
# ============================================================

def test_cte(engine):
    result = _ex(engine, {"$sql": [
        ["$with", {
            "$active_users": [
                ["$select", "$id", "$name"],
                ["$from", "$users"],
                ["$where", ["$eq", "$status", "active"]]
            ],
            "$big_spenders": [
                ["$select", "$user_id", ["$as", ["$sum", "$total"], "$total_spent"]],
                ["$from", "$orders"],
                ["$group-by", "$user_id"],
                ["$having", ["$gt", ["$sum", "$total"], 1000]]
            ]
        }],
        ["$select", "$a.name", "$b.total_spent"],
        ["$from", ["$as", "$active_users", "$a"]],
        ["$join", ["$as", "$big_spenders", "$b"], ["$eq", "$a.id", "$b.user_id"]]
    ]})
    assert "with " in result
    assert "active_users as (" in result
    assert "big_spenders as (" in result
    assert "select a.name, b.total_spent" in result
    assert "from active_users as a" in result
    assert "join big_spenders as b" in result


# ============================================================
# Case 5: Subquery IN
# ============================================================

def test_subquery_in(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$name", "$email"],
        ["$from", "$users"],
        ["$where", ["$in", "$id", [
            ["$select", "$user_id"],
            ["$from", "$orders"],
            ["$where", ["$gt", "$total", 1000]]
        ]]]
    ]})
    assert "id in (" in result
    assert "select user_id" in result
    assert "from orders" in result


# ============================================================
# Case 6: GROUP BY + aggregates + HAVING + ORDER BY
# ============================================================

def test_group_by_aggregates(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$category",
            ["$as", ["$count", "$*"], "$cnt"],
            ["$as", ["$avg", "$price"], "$avg_price"],
            ["$as", ["$max", "$price"], "$max_price"]],
        ["$from", "$products"],
        ["$where", ["$ne", "$deleted", True]],
        ["$group-by", "$category"],
        ["$having", ["$gt", ["$count", "$*"], 10]],
        ["$order-by", "$avg_price", "$desc"],
        ["$limit", 50]
    ]})
    assert "group by category" in result
    assert "having" in result
    assert "count(*)" in result
    assert "order by avg_price desc" in result
    assert "limit 50" in result
    assert "(count(*)) as cnt" in result
    assert "(avg(price)) as avg_price" in result
    assert "(max(price)) as max_price" in result


# ============================================================
# Case 7: INSERT
# ============================================================

def test_insert_single(engine):
    result = _ex(engine, {"$sql": [
        ["$insert-into", "$users", "$name", "$age", "$email"],
        ["$values", "Alice", 30, "alice@example.com"]
    ]})
    assert "insert into users" in result
    assert "(name, age, email)" in result
    assert "values" in result
    assert "'Alice'" in result


def test_insert_multi_row(engine):
    result = _ex(engine, {"$sql": [
        ["$insert-into", "$products", "$name", "$price"],
        ["$values", "Widget", 9.99],
        ["$values", "Gadget", 19.99],
        ["$values", "Doohickey", 4.99]
    ]})
    assert "insert into products" in result
    assert "('Widget', 9.99)" in result
    assert "('Gadget', 19.99)" in result
    assert "('Doohickey', 4.99)" in result


def test_insert_upsert(engine):
    result = _ex(engine, {"$sql": [
        ["$insert-into", "$users", "$name", "$age", "$email"],
        ["$values", "Alice", 31, "alice@new.com"],
        ["$on-conflict", "$name"],
        ["$do-update", {"$age": ["$excluded", "$age"], "$email": ["$excluded", "$email"]}]
    ]})
    assert "on conflict (name)" in result
    assert "do update set" in result
    assert "excluded.age" in result
    assert "excluded.email" in result


# ============================================================
# Case 8: UPDATE
# ============================================================

def test_update(engine):
    result = _ex(engine, {"$sql": [
        ["$update", "$users"],
        ["$set", {"$age": 31, "$status": "active"}],
        ["$where", ["$eq", "$id", 42]]
    ]})
    assert "update users" in result
    assert "set age = 31" in result
    assert "status = 'active'" in result
    assert "id = 42" in result


# ============================================================
# Case 9: $symbol (quoted identifiers)
# ============================================================

def test_symbol_quoted_identifiers(engine):
    result = _ex(engine, {"$sql": [
        ["$select", {"$symbol": "First Name"}, {"$symbol": "Last Name"}],
        ["$from", {"$symbol": "User Table"}],
        ["$where", ["$eq", {"$symbol": "Status"}, "active"]],
        ["$order-by", {"$symbol": "First Name"}]
    ]})
    assert '"First Name"' in result
    assert '"Last Name"' in result
    assert '"User Table"' in result
    assert '"Status"' in result


# ============================================================
# Case 10: $$ escape + null + boolean
# ============================================================

def test_dollar_escape(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$name", "$sku"],
        ["$from", "$products"],
        ["$where", ["$and",
            ["$like", "$sku", "$$PROMO-%"],
            ["$is-not", "$deleted_at", None],
            ["$eq", "$is_active", True]
        ]]
    ]})
    assert "sku like '$PROMO-%'" in result
    assert "deleted_at is not null" in result
    assert "is_active = true" in result


def test_null_and_boolean(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$x"],
        ["$from", "$t"],
        ["$where", ["$and",
            ["$is", "$col1", None],
            ["$is-not", "$col2", None],
            ["$eq", "$col3", True],
            ["$eq", "$col4", False]
        ]]
    ]})
    assert "col1 is null" in result
    assert "col2 is not null" in result
    assert "col3 = true" in result
    assert "col4 = false" in result


# ============================================================
# Case 11: CASE WHEN
# ============================================================

def test_case_when(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$name", "$score",
            ["$as",
                ["$case",
                    ["$when", ["$gte", "$score", 90], "A"],
                    ["$when", ["$gte", "$score", 80], "B"],
                    ["$when", ["$gte", "$score", 70], "C"],
                    ["$else", "F"]
                ],
                "$grade"
            ]
        ],
        ["$from", "$students"],
        ["$order-by", "$score", "$desc"]
    ]})
    assert "case" in result
    assert "when" in result
    assert "then" in result
    assert "else 'F'" in result
    assert "end) as grade" in result


# ============================================================
# Case 12: DELETE
# ============================================================

def test_delete(engine):
    result = _ex(engine, {"$sql": [
        ["$delete-from", "$sessions"],
        ["$where", ["$lt", "$expired_at", "2024-01-01"]]
    ]})
    assert "delete from sessions" in result
    assert "expired_at < '2024-01-01'" in result


# ============================================================
# Extra: CROSS JOIN
# ============================================================

def test_cross_join(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$u.name", "$d.dept_name"],
        ["$from", ["$as", "$users", "$u"]],
        ["$cross-join", ["$as", "$departments", "$d"]]
    ]})
    assert "cross join departments as d" in result


# ============================================================
# Extra: Multi-table JOIN with compound condition
# ============================================================

def test_multi_join(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$u.name", "$o.total", "$p.product_name"],
        ["$from", ["$as", "$users", "$u"]],
        ["$join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
        ["$join", ["$as", "$products", "$p"], ["$eq", "$o.product_id", "$p.id"]],
        ["$where", ["$and",
            ["$gt", "$o.total", 100],
            ["$eq", "$u.status", "active"]
        ]]
    ]})
    assert "join orders as o" in result
    assert "join products as p" in result
    assert "o.product_id = p.id" in result


# ============================================================
# Extra: ORDER BY ASC / LIMIT + OFFSET
# ============================================================

def test_order_by_asc(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$name"],
        ["$from", "$users"],
        ["$order-by", "$name", "$asc"]
    ]})
    assert "order by name asc" in result


def test_limit_offset(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$name"],
        ["$from", "$users"],
        ["$limit", 10],
        ["$offset", 20]
    ]})
    assert "limit 10" in result
    assert "offset 20" in result


# ============================================================
# Edge cases
# ============================================================

def test_empty_expression(engine):
    result = _ex(engine, {"$sql": [
        ["$select"],
        ["$from", "$users"]
    ]})
    assert "select" in result
    assert "from users" in result


def test_all_comparison_operators(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$x"],
        ["$from", "$t"],
        ["$where", ["$and",
            ["$eq", "$a", "$b"],
            ["$ne", "$c", "$d"],
            ["$gt", "$e", 5],
            ["$gte", "$f", 10],
            ["$lt", "$g", 100],
            ["$lte", "$h", 200]
        ]]
    ]})
    assert "a = b" in result
    assert "c != d" in result
    assert "e > 5" in result
    assert "f >= 10" in result
    assert "g < 100" in result
    assert "h <= 200" in result


def test_plain_string_table(engine):
    """Table name without $ prefix is a string literal."""
    result = _ex(engine, {"$sql": [
        ["$select", "$x"],
        ["$from", "my_table"]
    ]})
    assert "from 'my_table'" in result


def test_or_operator(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$x"],
        ["$from", "$t"],
        ["$where", ["$or",
            ["$eq", "$status", "active"],
            ["$eq", "$status", "pending"]
        ]]
    ]})
    assert " or " in result
    assert "(status = 'active')" in result


def test_order_by_desc(engine):
    result = _ex(engine, {"$sql": [
        ["$select", "$x"],
        ["$from", "$t"],
        ["$order-by", "$x", "$desc"]
    ]})
    assert "order by x desc" in result
