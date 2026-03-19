//! Tests for meta mechanism in JSE.
//!
//! Meta mechanism allows passing additional metadata to functors through the
//! environment. When an expression like {"$operator": value, "meta_key": meta_value}
//! is evaluated, the metadata is set in the environment before the functor is called,
//! and cleared after the functor returns.

use std::rc::Rc;
use std::cell::RefCell;
use std::collections::HashMap;
use serde_json::{json, Value};
use jse::{Engine, Env, Functor, ast::AstError};

/// Helper to evaluate meta values (which might be AST nodes)
fn eval_meta_value(_env: &Rc<RefCell<Env>>, value: &Value) -> Result<Value, AstError> {
    // In Rust implementation, values are already evaluated
    Ok(value.clone())
}

/// A functor that returns the current metadata from the environment
fn get_meta(env: &Rc<RefCell<Env>>, _args: &[Value]) -> Result<Value, AstError> {
    let meta = env.borrow().get_meta().clone();
    let mut result = serde_json::Map::new();

    for (k, v) in meta {
        let evaluated = eval_meta_value(env, &v)?;
        result.insert(k, evaluated);
    }

    Ok(Value::Object(result))
}

/// A functor that returns a specific key from metadata
fn get_meta_key(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    if args.is_empty() {
        return Ok(Value::Null);
    }

    let key = match &args[0] {
        Value::String(s) => s.clone(),
        _ => return Ok(Value::Null),
    };

    let meta = env.borrow().get_meta().clone();
    if meta.is_empty() {
        return Ok(Value::Null);
    }

    match meta.get(&key) {
        Some(value) => eval_meta_value(env, value),
        None => Ok(Value::Null),
    }
}

/// A functor that returns all metadata plus arguments
fn meta_with_args(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    let meta = env.borrow().get_meta().clone();
    let mut meta_result = serde_json::Map::new();

    for (k, v) in meta {
        let evaluated = eval_meta_value(env, &v)?;
        meta_result.insert(k, evaluated);
    }

    Ok(json!({
        "meta": Value::Object(meta_result),
        "args": Value::Array(args.to_vec())
    }))
}

// Thread-local storage for side effect testing
thread_local! {
    static LAST_META: RefCell<HashMap<String, Value>> = RefCell::new(HashMap::new());
}

/// A functor that stores meta and returns the argument unchanged
fn identity_with_meta(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    let meta = env.borrow().get_meta().clone();

    let mut stored = HashMap::new();
    for (k, v) in meta {
        let evaluated = eval_meta_value(env, &v)?;
        stored.insert(k, evaluated);
    }
    LAST_META.with(|last_meta| {
        *last_meta.borrow_mut() = stored;
    });

    if !args.is_empty() {
        eval_meta_value(env, &args[0])
    } else {
        Ok(Value::Null)
    }
}

/// Create an engine with meta-related functors
fn create_engine_with_meta_functors() -> Engine {
    let env = Rc::new(RefCell::new(Env::new()));

    let mut functors: HashMap<&'static str, Functor> = HashMap::new();
    functors.insert("$get_meta", get_meta);
    functors.insert("$get_meta_key", get_meta_key);
    functors.insert("$meta_with_args", meta_with_args);
    functors.insert("$identity", identity_with_meta);

    for (name, functor) in functors {
        env.borrow_mut().register_functor(name.to_string(), functor);
    }

    Engine::new(env)
}

// --- Basic Meta Passing Tests ---

#[test]
fn test_meta_basic_passing() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta": null,
        "key1": "value1",
        "key2": 42
    });

    let result = engine.execute(&expr).expect("execute error");

    let result_map = result.as_object().expect("expected object result");
    assert!(result_map.contains_key("key1"), "expected key1 in result");
    assert!(result_map.contains_key("key2"), "expected key2 in result");
}

#[test]
fn test_meta_string_value() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "name",
        "name": "test_value"
    });

    let result = engine.execute(&expr).expect("execute error");

    assert_eq!(result, json!("test_value"));
}

#[test]
fn test_meta_number_value() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "count",
        "count": 123
    });

    let result = engine.execute(&expr).expect("execute error");

    assert_eq!(result, json!(123));
}

// --- Multiple Metadata Keys Tests ---

#[test]
fn test_meta_multiple_keys() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta": null,
        "first": "one",
        "second": "two",
        "third": 3
    });

    let result = engine.execute(&expr).expect("execute error");

    let result_map = result.as_object().expect("expected object result");
    assert_eq!(result_map.get("first"), Some(&json!("one")));
    assert_eq!(result_map.get("second"), Some(&json!("two")));
    assert_eq!(result_map.get("third"), Some(&json!(3)));
}

// --- Meta With Arguments Tests ---

#[test]
fn test_meta_with_args() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$meta_with_args": ["arg1", "arg2"],
        "meta_key": "meta_value"
    });

    let result = engine.execute(&expr).expect("execute error");

    let result_map = result.as_object().expect("expected object result");
    assert!(result_map.contains_key("meta"), "expected 'meta' in result");
    assert!(result_map.contains_key("args"), "expected 'args' in result");

    let meta = result_map.get("meta").unwrap().as_object().unwrap();
    assert_eq!(meta.get("meta_key"), Some(&json!("meta_value")));
}

// --- Meta Lifecycle Tests ---

#[test]
fn test_meta_cleared_after_functor() {
    let engine = create_engine_with_meta_functors();

    // First call with metadata
    let expr1 = json!({
        "$get_meta": null,
        "temp_key": "temp_value"
    });

    let result1 = engine.execute(&expr1).expect("execute error");
    let result_map1 = result1.as_object().expect("expected object result");
    assert!(result_map1.contains_key("temp_key"), "expected temp_key in first result");

    // Second call without metadata - should return empty map
    let expr2 = json!({
        "$get_meta": null
    });

    let result2 = engine.execute(&expr2).expect("execute error");
    let result_map2 = result2.as_object().expect("expected object result");
    assert!(result_map2.is_empty(), "expected empty map, got {:?}", result_map2);
}

#[test]
fn test_meta_available_during_functor_execution() {
    let engine = create_engine_with_meta_functors();

    // Clear last meta
    LAST_META.with(|m| *m.borrow_mut() = HashMap::new());

    let expr = json!({
        "$identity": "return_value",
        "stored_key": "stored_value"
    });

    let result = engine.execute(&expr).expect("execute error");

    // The result should be the argument
    assert_eq!(result, json!("return_value"));

    // But the functor should have captured the meta
    LAST_META.with(|last_meta| {
        let meta = last_meta.borrow();
        assert!(!meta.is_empty(), "expected lastMeta to be set");
        assert_eq!(meta.get("stored_key"), Some(&json!("stored_value")));
    });
}

// --- Metadata Value Types Tests ---

#[test]
fn test_meta_object_value() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "config",
        "config": {
            "nested": "value",
            "number": 42
        }
    });

    let result = engine.execute(&expr).expect("execute error");

    let config = result.as_object().expect("expected object");
    assert_eq!(config.get("nested"), Some(&json!("value")));
    assert_eq!(config.get("number"), Some(&json!(42)));
}

#[test]
fn test_meta_list_value() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "items",
        "items": [1, 2, 3]
    });

    let result = engine.execute(&expr).expect("execute error");

    let items = result.as_array().expect("expected array");
    assert_eq!(items.len(), 3);
    assert_eq!(items[0], json!(1));
    assert_eq!(items[1], json!(2));
    assert_eq!(items[2], json!(3));
}

#[test]
fn test_meta_null_value() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "nullable",
        "nullable": null
    });

    let result = engine.execute(&expr).expect("execute error");

    assert!(result.is_null());
}

#[test]
fn test_meta_boolean_true() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "flag",
        "flag": true
    });

    let result = engine.execute(&expr).expect("execute error");

    assert_eq!(result, json!(true));
}

#[test]
fn test_meta_boolean_false() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "flag",
        "flag": false
    });

    let result = engine.execute(&expr).expect("execute error");

    assert_eq!(result, json!(false));
}

#[test]
fn test_meta_nested_list_value() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "nested",
        "nested": [[1, 2], [3, 4]]
    });

    let result = engine.execute(&expr).expect("execute error");

    let nested = result.as_array().expect("expected array");
    assert_eq!(nested.len(), 2);
}

#[test]
fn test_meta_complex_object() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "complex",
        "complex": {
            "level1": {
                "level2": "deep_value"
            },
            "array": [1, 2, 3]
        }
    });

    let result = engine.execute(&expr).expect("execute error");

    let complex = result.as_object().expect("expected object");
    let level1 = complex.get("level1").unwrap().as_object().unwrap();
    assert_eq!(level1.get("level2"), Some(&json!("deep_value")));

    let arr = complex.get("array").unwrap().as_array().unwrap();
    assert_eq!(arr.len(), 3);
}

// --- Missing Metadata Tests ---

#[test]
fn test_meta_missing_key() {
    let engine = create_engine_with_meta_functors();

    let expr = json!({
        "$get_meta_key": "nonexistent"
    });

    let result = engine.execute(&expr).expect("execute error");

    assert!(result.is_null(), "expected null for missing key, got {:?}", result);
}
