require_relative "test_helper"

class TestSql < Minitest::Test
  include JSE::TestHelper

  def setup
    @engine = engine_with_sql
  end

  def exec(expr)
    @engine.execute(expr)
  end

  def test_select_from
    sql = exec({ "$sql" => [["$select", "$name", "$age"], ["$from", "$users"]] })
    assert_includes sql, "select name, age"
    assert_includes sql, "from users"
  end

  def test_nested_and_or
    sql = exec({ "$sql" => [
      ["$select", "$name", "$age"],
      ["$from", "$users"],
      ["$where", ["$and",
        ["$gt", "$age", 18],
        ["$or", ["$eq", "$status", "active"], ["$eq", "$role", "admin"]]]]
    ] })
    assert_includes sql, "age > 18"
    assert_includes sql, "status = 'active'"
    assert_includes sql, "role = 'admin'"
  end

  def test_join_with_alias
    sql = exec({ "$sql" => [
      ["$select", "$u.name", "$o.total"],
      ["$from", ["$as", "$users", "$u"]],
      ["$join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
      ["$where", ["$gt", "$o.total", 100]]
    ] })
    assert_includes sql, "users as u"
    assert_includes sql, "join orders as o"
    assert_includes sql, "u.id = o.user_id"
  end

  def test_left_join_null
    sql = exec({ "$sql" => [
      ["$select", "$u.name", "$o.total"],
      ["$from", ["$as", "$users", "$u"]],
      ["$left-join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
      ["$where", ["$is", "$o.total", nil]]
    ] })
    assert_includes sql, "left join"
    assert_includes sql, "o.total is null"
  end

  def test_insert
    sql = exec({ "$sql" => [
      ["$insert-into", "$users", "$name", "$age", "$email"],
      ["$values", "Alice", 30, "alice@example.com"]
    ] })
    assert_includes sql, "insert into users"
    assert_includes sql, "'Alice'"
  end

  def test_delete
    sql = exec({ "$sql" => [
      ["$delete-from", "$sessions"],
      ["$where", ["$lt", "$expired_at", "2024-01-01"]]
    ] })
    assert_includes sql, "delete from sessions"
    assert_includes sql, "expired_at < '2024-01-01'"
  end

  def test_update
    sql = exec({ "$sql" => [
      ["$update", "$users"],
      ["$set", { "$age" => 31, "$status" => "active" }],
      ["$where", ["$eq", "$id", 42]]
    ] })
    assert_includes sql, "update users"
    assert_includes sql, "age = 31"
    assert_includes sql, "id = 42"
  end

  def test_dollar_escape
    sql = exec({ "$sql" => [
      ["$select", "$name", "$sku"],
      ["$from", "$products"],
      ["$where", ["$and",
        ["$like", "$sku", "$$PROMO-%"],
        ["$is-not", "$deleted_at", nil],
        ["$eq", "$is_active", true]]]
    ] })
    assert_includes sql, "sku like '$PROMO-%'"
    assert_includes sql, "deleted_at is not null"
    assert_includes sql, "is_active = true"
  end

  def test_group_by_aggregates
    sql = exec({ "$sql" => [
      ["$select", "$category",
        ["$as", ["$count", "$*"], "$cnt"],
        ["$as", ["$avg", "$price"], "$avg_price"]],
      ["$from", "$products"],
      ["$group-by", "$category"],
      ["$order-by", "$avg_price", "$desc"],
      ["$limit", 50]
    ] })
    assert_includes sql, "group by category"
    assert_includes sql, "count(*)"
    assert_includes sql, "order by avg_price desc"
    assert_includes sql, "limit 50"
  end

  def test_cross_join
    sql = exec({ "$sql" => [
      ["$select", "$u.name", "$d.dept_name"],
      ["$from", ["$as", "$users", "$u"]],
      ["$cross-join", ["$as", "$departments", "$d"]]
    ] })
    assert_includes sql, "cross join departments as d"
  end

  def test_symbol_quoted_identifiers
    sql = exec({ "$sql" => [
      ["$select", { "$symbol" => "First Name" }, { "$symbol" => "Last Name" }],
      ["$from", { "$symbol" => "User Table" }]
    ] })
    assert_includes sql, '"First Name"'
    assert_includes sql, '"Last Name"'
    assert_includes sql, '"User Table"'
  end

  def test_multi_row_insert
    sql = exec({ "$sql" => [
      ["$insert-into", "$products", "$name", "$price"],
      ["$values", "Widget", 9.99],
      ["$values", "Gadget", 19.99],
      ["$values", "Doohickey", 4.99]
    ] })
    assert_includes sql, "insert into products"
    assert_includes sql, "('Widget', 9.99)"
    assert_includes sql, "('Gadget', 19.99)"
    assert_includes sql, "('Doohickey', 4.99)"
  end

  def test_upsert
    sql = exec({ "$sql" => [
      ["$insert-into", "$users", "$name", "$age", "$email"],
      ["$values", "Alice", 31, "alice@new.com"],
      ["$on-conflict", "$name"],
      ["$do-update", { "$age" => ["$excluded", "$age"], "$email" => ["$excluded", "$email"] }]
    ] })
    assert_includes sql, "on conflict (name)"
    assert_includes sql, "do update set"
    assert_includes sql, "excluded.age"
    assert_includes sql, "excluded.email"
  end

  def test_case_when
    sql = exec({ "$sql" => [
      ["$select", "$name", "$score",
        ["$as", ["$case",
          ["$when", ["$gte", "$score", 90], "A"],
          ["$when", ["$gte", "$score", 80], "B"],
          ["$when", ["$gte", "$score", 70], "C"],
          ["$else", "F"]], "$grade"]],
      ["$from", "$students"],
      ["$order-by", "$score", "$desc"]
    ] })
    assert_includes sql, "case"
    assert_includes sql, "when score >= 90 then 'A'"
    assert_includes sql, "else 'F'"
    assert_includes sql, "end) as grade"
  end

  def test_multi_join
    sql = exec({ "$sql" => [
      ["$select", "$u.name", "$o.total", "$p.product_name"],
      ["$from", ["$as", "$users", "$u"]],
      ["$join", ["$as", "$orders", "$o"], ["$eq", "$u.id", "$o.user_id"]],
      ["$join", ["$as", "$products", "$p"], ["$eq", "$o.product_id", "$p.id"]],
      ["$where", ["$and", ["$gt", "$o.total", 100], ["$eq", "$u.status", "active"]]]
    ] })
    assert_includes sql, "join orders as o"
    assert_includes sql, "join products as p"
    assert_includes sql, "o.product_id = p.id"
  end

  # Legacy $query backward compat
  def test_legacy_query_basic
    env = JSE::Env.new
    env.load(JSE::Functors::Builtin::BUILTIN_FUNCTORS)
    env.load(JSE::Functors::Utils::UTILS_FUNCTORS)
    env.load(JSE::Functors::SQL::SQL_FUNCTORS)
    engine = JSE::Engine.new(env)

    sql = engine.execute({ "$query" => ["$quote", ["$pattern", "$*", "author of", "$*"]] })
    assert_includes sql, "select"
    assert_includes sql, "from statement"
    assert_includes sql, "author of"
  end
end
