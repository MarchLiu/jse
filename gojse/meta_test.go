package jse

import (
	"testing"
)

// Tests for meta mechanism in JSE.
//
// Meta mechanism allows passing additional metadata to functors through the
// environment. When an expression like {"$operator": value, "meta_key": meta_value}
// is evaluated, the metadata is set in the environment before the functor is called,
// and cleared after the functor returns.

// Helper to evaluate meta values (which might be AST nodes)
func evalMetaValue(env *Env, value interface{}) (interface{}, error) {
	// Check if value is an AstNode by trying to call Apply
	if node, ok := value.(interface {
		Apply(interface{}) (interface{}, error)
	}); ok {
		return node.Apply(env)
	}
	return value, nil
}

// A functor that returns the current metadata from the environment
func getMeta(env interface{}, args []interface{}) (interface{}, error) {
	e := env.(*Env)
	meta := e.GetMeta()
	result := make(map[string]interface{})
	for k, v := range meta {
		evaluated, err := evalMetaValue(e, v)
		if err != nil {
			return nil, err
		}
		result[k] = evaluated
	}
	return result, nil
}

// A functor that returns a specific key from metadata
func getMetaKey(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return nil, nil
	}
	key, ok := args[0].(string)
	if !ok {
		return nil, nil
	}
	e := env.(*Env)
	meta := e.GetMeta()
	if meta == nil || len(meta) == 0 {
		return nil, nil
	}
	value, exists := meta[key]
	if !exists {
		return nil, nil
	}
	return evalMetaValue(e, value)
}

// A functor that returns all metadata plus arguments
func metaWithArgs(env interface{}, args []interface{}) (interface{}, error) {
	e := env.(*Env)
	meta := e.GetMeta()
	result := map[string]interface{}{
		"meta": make(map[string]interface{}),
		"args": args,
	}
	metaResult := result["meta"].(map[string]interface{})
	for k, v := range meta {
		evaluated, err := evalMetaValue(e, v)
		if err != nil {
			return nil, err
		}
		metaResult[k] = evaluated
	}
	return result, nil
}

// Store for side effect testing
var lastMeta map[string]interface{}

// A functor that stores meta and returns the argument unchanged
func identityWithMeta(env interface{}, args []interface{}) (interface{}, error) {
	e := env.(*Env)
	meta := e.GetMeta()
	lastMeta = make(map[string]interface{})
	for k, v := range meta {
		evaluated, err := evalMetaValue(e, v)
		if err != nil {
			return nil, err
		}
		lastMeta[k] = evaluated
	}
	if len(args) > 0 {
		return evalMetaValue(e, args[0])
	}
	return nil, nil
}

// createEngineWithMetaFunctors creates an engine with meta-related functors.
func createEngineWithMetaFunctors() *Engine {
	env := NewEnv()
	env.RegisterFunctor("$get_meta", getMeta)
	env.RegisterFunctor("$get_meta_key", getMetaKey)
	env.RegisterFunctor("$meta_with_args", metaWithArgs)
	env.RegisterFunctor("$identity", identityWithMeta)
	return NewEngine(env)
}

// --- Basic Meta Passing Tests ---

func TestMetaBasicPassing(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta": nil,
		"key1":      "value1",
		"key2":      42,
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	resultMap, ok := result.(map[string]interface{})
	if !ok {
		t.Fatalf("expected map result, got %T", result)
	}
	if _, exists := resultMap["key1"]; !exists {
		t.Error("expected key1 in result")
	}
	if _, exists := resultMap["key2"]; !exists {
		t.Error("expected key2 in result")
	}
}

func TestMetaStringValue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "name",
		"name":          "test_value",
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	if result != "test_value" {
		t.Fatalf("expected 'test_value', got %v", result)
	}
}

func TestMetaNumberValue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "count",
		"count":         123.0,
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	// JSON numbers are parsed as float64
	if count, ok := result.(float64); !ok || count != 123 {
		t.Fatalf("expected 123, got %v", result)
	}
}

// --- Multiple Metadata Keys Tests ---

func TestMetaMultipleKeys(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta": nil,
		"first":     "one",
		"second":    "two",
		"third":     3.0,
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	resultMap := result.(map[string]interface{})
	if resultMap["first"] != "one" {
		t.Fatalf("expected 'one', got %v", resultMap["first"])
	}
	if resultMap["second"] != "two" {
		t.Fatalf("expected 'two', got %v", resultMap["second"])
	}
	if resultMap["third"] != 3.0 {
		t.Fatalf("expected 3, got %v", resultMap["third"])
	}
}

// --- Meta With Arguments Tests ---

func TestMetaWithArgs(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$meta_with_args": []interface{}{"arg1", "arg2"},
		"meta_key":        "meta_value",
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	resultMap := result.(map[string]interface{})
	if _, exists := resultMap["meta"]; !exists {
		t.Fatal("expected 'meta' in result")
	}
	if _, exists := resultMap["args"]; !exists {
		t.Fatal("expected 'args' in result")
	}

	meta := resultMap["meta"].(map[string]interface{})
	if meta["meta_key"] != "meta_value" {
		t.Fatalf("expected 'meta_value', got %v", meta["meta_key"])
	}
}

// --- Meta Lifecycle Tests ---

func TestMetaClearedAfterFunctor(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	// First call with metadata
	expr1 := map[string]interface{}{
		"$get_meta": nil,
		"temp_key":  "temp_value",
	}
	result1, err := engine.Execute(expr1)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	resultMap1 := result1.(map[string]interface{})
	if _, exists := resultMap1["temp_key"]; !exists {
		t.Error("expected temp_key in first result")
	}

	// Second call without metadata - should return empty map
	expr2 := map[string]interface{}{
		"$get_meta": nil,
	}
	result2, err := engine.Execute(expr2)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}
	resultMap2 := result2.(map[string]interface{})
	if len(resultMap2) != 0 {
		t.Fatalf("expected empty map, got %v", resultMap2)
	}
}

func TestMetaAvailableDuringFunctorExecution(t *testing.T) {
	engine := createEngineWithMetaFunctors()
	lastMeta = nil

	expr := map[string]interface{}{
		"$identity":   "return_value",
		"stored_key":  "stored_value",
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	// The result should be the argument
	if result != "return_value" {
		t.Fatalf("expected 'return_value', got %v", result)
	}

	// But the functor should have captured the meta
	if lastMeta == nil {
		t.Fatal("expected lastMeta to be set")
	}
	if lastMeta["stored_key"] != "stored_value" {
		t.Fatalf("expected 'stored_value', got %v", lastMeta["stored_key"])
	}
}

// --- Metadata Value Types Tests ---

func TestMetaObjectValue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "config",
		"config": map[string]interface{}{
			"nested": "value",
			"number": 42.0,
		},
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	config := result.(map[string]interface{})
	if config["nested"] != "value" {
		t.Fatalf("expected 'value', got %v", config["nested"])
	}
	if config["number"] != 42.0 {
		t.Fatalf("expected 42, got %v", config["number"])
	}
}

func TestMetaListValue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "items",
		"items":         []interface{}{1.0, 2.0, 3.0},
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	items := result.([]interface{})
	if len(items) != 3 {
		t.Fatalf("expected 3 items, got %d", len(items))
	}
	if items[0] != 1.0 || items[1] != 2.0 || items[2] != 3.0 {
		t.Fatalf("expected [1, 2, 3], got %v", items)
	}
}

func TestMetaNullValue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "nullable",
		"nullable":      nil,
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	if result != nil {
		t.Fatalf("expected nil, got %v", result)
	}
}

func TestMetaBooleanTrue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "flag",
		"flag":          true,
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	if result != true {
		t.Fatalf("expected true, got %v", result)
	}
}

func TestMetaBooleanFalse(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "flag",
		"flag":          false,
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	if result != false {
		t.Fatalf("expected false, got %v", result)
	}
}

func TestMetaNestedListValue(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "nested",
		"nested":        []interface{}{[]interface{}{1.0, 2.0}, []interface{}{3.0, 4.0}},
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	nested := result.([]interface{})
	if len(nested) != 2 {
		t.Fatalf("expected 2 nested arrays, got %d", len(nested))
	}
}

func TestMetaComplexObject(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "complex",
		"complex": map[string]interface{}{
			"level1": map[string]interface{}{
				"level2": "deep_value",
			},
			"array": []interface{}{1.0, 2.0, 3.0},
		},
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	complex := result.(map[string]interface{})
	level1 := complex["level1"].(map[string]interface{})
	if level1["level2"] != "deep_value" {
		t.Fatalf("expected 'deep_value', got %v", level1["level2"])
	}

	arr := complex["array"].([]interface{})
	if len(arr) != 3 {
		t.Fatalf("expected 3 array items, got %d", len(arr))
	}
}

// --- Missing Metadata Tests ---

func TestMetaMissingKey(t *testing.T) {
	engine := createEngineWithMetaFunctors()

	expr := map[string]interface{}{
		"$get_meta_key": "nonexistent",
	}
	result, err := engine.Execute(expr)
	if err != nil {
		t.Fatalf("execute error: %v", err)
	}

	if result != nil {
		t.Fatalf("expected nil for missing key, got %v", result)
	}
}
