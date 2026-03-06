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
	  "$expr": ["$pattern", "$*", "author of", "$*"]
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
		!strings.Contains(sql, "from statement as s") ||
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
	  "$query": [
	    "$and",
	    [
	      ["$pattern", "Liu Xin", "author of", "$*"],
	      ["$pattern", "$*", "author of", "$*"]
	    ]
	  ]
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
	if !strings.Contains(sql, "select "+QueryFields) ||
		!strings.Contains(sql, "from statement") ||
		!strings.Contains(sql, "Liu Xin") ||
		!strings.Contains(sql, "author of") ||
		!strings.Contains(sql, " and ") ||
		!strings.Contains(sql, "offset 0") ||
		!strings.Contains(sql, "limit 100") {
		t.Fatalf("sql does not contain expected substrings: %q", sql)
	}
}
