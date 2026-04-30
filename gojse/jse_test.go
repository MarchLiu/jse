package jse

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/MarchLiu/jse/gojse/functors"
)

func newEngine() *Engine {
	return WithEnv()
}

func newEngineWithDefault() *Engine {
	return WithDefaultEnv()
}

func newEngineWithSQL() *Engine {
	env := NewEnv()
	env.Load(functors.BuiltinFunctors)
	env.Load(functors.UtilsFunctors)
	env.Load(functors.SQLFunctors)
	return NewEngine(env)
}

func TestBasicLiterals(t *testing.T) {
	e := newEngine()

	if v, err := e.Execute(42); err != nil || v != 42 {
		t.Fatalf("expected 42, got %v, err=%v", v, err)
	}
	if v, err := e.Execute(3.14); err != nil || v != 3.14 {
		t.Fatalf("expected 3.14, got %v, err=%v", v, err)
	}
	if v, err := e.Execute("hello"); err != nil || v != "hello" {
		t.Fatalf("expected hello, got %v, err=%v", v, err)
	}
	if v, err := e.Execute(true); err != nil || v != true {
		t.Fatalf("expected true, got %v, err=%v", v, err)
	}
	if v, err := e.Execute(false); err != nil || v != false {
		t.Fatalf("expected false, got %v, err=%v", v, err)
	}
	if v, err := e.Execute(nil); err != nil || v != nil {
		t.Fatalf("expected nil, got %v, err=%v", v, err)
	}
}

func TestArrayAndObject(t *testing.T) {
	e := newEngine()

	arr := []interface{}{1.0, 2.0, 3.0}
	v, err := e.Execute(arr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	out, ok := v.([]interface{})
	if !ok || len(out) != 3 {
		t.Fatalf("expected array of len 3, got %#v", v)
	}

	obj := map[string]interface{}{"a": 1.0, "b": "x"}
	v2, err := e.Execute(obj)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	outObj, ok := v2.(map[string]interface{})
	if !ok || len(outObj) != 2 || outObj["a"] != 1.0 || outObj["b"] != "x" {
		t.Fatalf("unexpected object result: %#v", v2)
	}
}

func TestLogic(t *testing.T) {
	e := newEngineWithDefault()

	// $and
	if v, err := e.Execute([]interface{}{"$and", true, true, true}); err != nil || v != true {
		t.Fatalf("$and true,true,true => true, got %v, err=%v", v, err)
	}
	if v, err := e.Execute([]interface{}{"$and", true, false, true}); err != nil || v != false {
		t.Fatalf("$and true,false,true => false, got %v, err=%v", v, err)
	}

	// $or
	if v, err := e.Execute([]interface{}{"$or", false, false, true}); err != nil || v != true {
		t.Fatalf("$or false,false,true => true, got %v, err=%v", v, err)
	}
	if v, err := e.Execute([]interface{}{"$or", false, false, false}); err != nil || v != false {
		t.Fatalf("$or false,false,false => false, got %v, err=%v", v, err)
	}

	// $not
	if v, err := e.Execute([]interface{}{"$not", true}); err != nil || v != false {
		t.Fatalf("$not true => false, got %v, err=%v", v, err)
	}
	if v, err := e.Execute([]interface{}{"$not", false}); err != nil || v != true {
		t.Fatalf("$not false => true, got %v, err=%v", v, err)
	}

	// nested
	expr := []interface{}{
		"$or",
		[]interface{}{"$and", true, []interface{}{"$not", false}},
		[]interface{}{"$and", false, true},
	}
	if v, err := e.Execute(expr); err != nil || v != true {
		t.Fatalf("nested expr => true, got %v, err=%v", v, err)
	}
}

func TestQueryBasic(t *testing.T) {
	e := newEngineWithSQL()

	raw := []byte(`{
	  "$query": ["$quote", ["$pattern", "$*", "author of", "$*"]]
	}`)
	var query map[string]interface{}
	if err := json.Unmarshal(raw, &query); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	v, err := e.Execute(query)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	sql, ok := v.(string)
	if !ok {
		t.Fatalf("expected string sql, got %#v", v)
	}
	// Loose checking - look for keywords, not exact format
	if !strings.Contains(sql, "select") ||
		!strings.Contains(sql, "subject, predicate, object, meta") ||
		!strings.Contains(sql, "from statement") ||
		!strings.Contains(sql, "author of") ||
		!strings.Contains(sql, "triple") ||
		!strings.Contains(sql, "offset 0") ||
		!strings.Contains(sql, "limit 100") {
		t.Fatalf("sql does not contain expected substrings: %q", sql)
	}
}

func TestQueryCombined(t *testing.T) {
	e := newEngineWithSQL()

	raw := []byte(`{
	  "$query": {
	    "$quote": [
	      "$and",
	      ["$pattern", "Liu Xin", "author of", "$*"],
	      ["$pattern", "$*", "author of", "$*"]
	    ]
	  }
	}`)
	var query map[string]interface{}
	if err := json.Unmarshal(raw, &query); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	v, err := e.Execute(query)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	sql, ok := v.(string)
	if !ok {
		t.Fatalf("expected string sql, got %#v", v)
	}
	if !strings.Contains(sql, "select") ||
		!strings.Contains(sql, "subject, predicate, object, meta") ||
		!strings.Contains(sql, "from statement") ||
		!strings.Contains(sql, "Liu Xin") ||
		!strings.Contains(sql, "author of") ||
		!strings.Contains(sql, " and ") ||
		!strings.Contains(sql, "offset 0") ||
		!strings.Contains(sql, "limit 100") {
		t.Fatalf("sql does not contain expected substrings: %q", sql)
	}
}

func unmarshalExecute(t *testing.T, e *Engine, rawJSON string) string {
	t.Helper()
	var expr map[string]interface{}
	if err := json.Unmarshal([]byte(rawJSON), &expr); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	v, err := e.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	sql, ok := v.(string)
	if !ok {
		t.Fatalf("expected string sql, got %#v", v)
	}
	return sql
}

func TestSqlSelectFrom(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [["$select","$name","$age"],["$from","$users"]]
	}`)
	if !strings.Contains(sql, "select name, age") || !strings.Contains(sql, "from users") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlNestedAndOr(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$select","$name","$age"],
			["$from","$users"],
			["$where",["$and",
				["$gt","$age",18],
				["$or",["$eq","$status","active"],["$eq","$role","admin"]]]]
		]
	}`)
	if !strings.Contains(sql, "age > 18") ||
		!strings.Contains(sql, "status = 'active'") ||
		!strings.Contains(sql, "role = 'admin'") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlJoinWithAlias(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$select","$u.name","$o.total"],
			["$from",["$as","$users","$u"]],
			["$join",["$as","$orders","$o"],["$eq","$u.id","$o.user_id"]],
			["$where",["$gt","$o.total",100]]
		]
	}`)
	if !strings.Contains(sql, "users as u") ||
		!strings.Contains(sql, "join orders as o") ||
		!strings.Contains(sql, "u.id = o.user_id") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlLeftJoinNull(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$select","$u.name","$o.total"],
			["$from",["$as","$users","$u"]],
			["$left-join",["$as","$orders","$o"],["$eq","$u.id","$o.user_id"]],
			["$where",["$is","$o.total",null]]
		]
	}`)
	if !strings.Contains(sql, "left join") ||
		!strings.Contains(sql, "o.total is null") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlInsert(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$insert-into","$users","$name","$age","$email"],
			["$values","Alice",30,"alice@example.com"]
		]
	}`)
	if !strings.Contains(sql, "insert into users") ||
		!strings.Contains(sql, "values") ||
		!strings.Contains(sql, "'Alice'") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlDelete(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$delete-from","$sessions"],
			["$where",["$lt","$expired_at","2024-01-01"]]
		]
	}`)
	if !strings.Contains(sql, "delete from sessions") ||
		!strings.Contains(sql, "expired_at < '2024-01-01'") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlUpdate(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$update","$users"],
			["$set",{"$age":31,"$status":"active"}],
			["$where",["$eq","$id",42]]
		]
	}`)
	if !strings.Contains(sql, "update users") ||
		!strings.Contains(sql, "age = 31") ||
		!strings.Contains(sql, "id = 42") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlDollarEscape(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$select","$name","$sku"],
			["$from","$products"],
			["$where",["$and",
				["$like","$sku","$$PROMO-%"],
				["$is-not","$deleted_at",null],
				["$eq","$is_active",true]]]
		]
	}`)
	if !strings.Contains(sql, "sku like '$PROMO-%'") ||
		!strings.Contains(sql, "deleted_at is not null") ||
		!strings.Contains(sql, "is_active = true") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlGroupByAggregates(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$select","$category",
				["$as",["$count","$*"],"$cnt"],
				["$as",["$avg","$price"],"$avg_price"]],
			["$from","$products"],
			["$group-by","$category"],
			["$order-by","$avg_price","$desc"],
			["$limit",50]
		]
	}`)
	if !strings.Contains(sql, "group by category") ||
		!strings.Contains(sql, "count(*)") ||
		!strings.Contains(sql, "order by avg_price desc") ||
		!strings.Contains(sql, "limit 50") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}

func TestSqlCrossJoin(t *testing.T) {
	e := newEngineWithSQL()
	sql := unmarshalExecute(t, e, `{
		"$sql": [
			["$select","$u.name","$d.dept_name"],
			["$from",["$as","$users","$u"]],
			["$cross-join",["$as","$departments","$d"]]
		]
	}`)
	if !strings.Contains(sql, "cross join departments as d") {
		t.Fatalf("unexpected sql: %q", sql)
	}
}
