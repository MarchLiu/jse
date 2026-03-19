/// Meta tests for JSE engine (internal tests)
///
/// Meta mechanism allows passing additional metadata to functors through the
/// environment. When an expression like {"$operator": value, "meta_key": meta_value}
/// is evaluated, the metadata is set in the environment before the functor is called,
/// and cleared after the functor returns.

// Helper to create an object from key-value pairs
fn meta_make_object1(k1 : String, v1 : JseValue) -> Map[String, JseValue] {
  let obj = Map::new()
  map_put(obj, k1, v1)
}

fn meta_make_object2(k1 : String, v1 : JseValue, k2 : String, v2 : JseValue) -> Map[String, JseValue] {
  let obj = Map::new()
  let obj2 = map_put(obj, k1, v1)
  map_put(obj2, k2, v2)
}

fn meta_make_object3(k1 : String, v1 : JseValue, k2 : String, v2 : JseValue, k3 : String, v3 : JseValue) -> Map[String, JseValue] {
  let obj = Map::new()
  let mut obj2 = map_put(obj, k1, v1)
  obj2 = map_put(obj2, k2, v2)
  map_put(obj2, k3, v3)
}

// Global storage for side effect testing
let last_meta : Ref[Map[String, JseValue]] = Ref::new(Map::new())

// Functor: returns the current metadata from the environment
fn get_meta_functor(env : Env, _args : Array[JseValue]) -> Result[JseValue, String] {
  let meta = get_meta(env)
  Ok(jse_object(meta))
}

// Functor: returns a specific key from metadata
fn get_meta_key_functor(env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() == 0 {
    return Ok(jse_null())
  }
  match args[0] {
    JseValue::StringValue(key) => {
      let meta = get_meta(env)
      match meta.get(key) {
        Some(v) => Ok(v)
        None => Ok(jse_null())
      }
    }
    _ => Ok(jse_null())
  }
}

// Functor: returns all metadata plus arguments
fn meta_with_args_functor(env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  let meta = get_meta(env)
  let result = Map::new()
  let result2 = map_put(result, "meta", jse_object(meta))
  let result3 = map_put(result2, "args", jse_array(args))
  Ok(jse_object(result3))
}

// Functor: stores meta and returns the argument unchanged
fn identity_with_meta_functor(env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  let meta = get_meta(env)
  last_meta.val = meta
  if args.length() > 0 {
    Ok(args[0])
  } else {
    Ok(jse_null())
  }
}

// Create an engine with meta-related functors
fn create_engine_with_meta_functors() -> Engine {
  let env_val = new()

  // Register meta functors
  register_functor(env_val, "$get_meta", get_meta_functor)
  register_functor(env_val, "$get_meta_key", get_meta_key_functor)
  register_functor(env_val, "$meta_with_args", meta_with_args_functor)
  register_functor(env_val, "$identity", identity_with_meta_functor)

  engine_new(env_val)
}

// --- Basic Meta Passing Tests ---

test "meta basic passing" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta": null, "key1": "value1", "key2": 42}
  let expr = jse_object(meta_make_object3(
    "$get_meta", jse_null(),
    "key1", jse_string("value1"),
    "key2", jse_number(42)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="2")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta string value" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "name", "name": "test_value"}
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("name"),
    "name", jse_string("test_value")
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::StringValue(s) => inspect(s, content="test_value")
        _ => abort("Expected StringValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta number value" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "count", "count": 123}
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("count"),
    "count", jse_number(123)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::NumberValue(n) => inspect(n, content="123")
        _ => abort("Expected NumberValue")
      }
    }
    Err(e) => abort(e)
  }
}

// --- Multiple Metadata Keys Tests ---

test "meta multiple keys" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta": null, "first": "one", "second": "two", "third": 3}
  let expr = jse_object(meta_make_object3(
    "$get_meta", jse_null(),
    "first", jse_string("one"),
    "second", jse_string("two")
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="2")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }
}

// --- Meta With Arguments Tests ---

test "meta with args" {
  let engine = create_engine_with_meta_functors()
  // {"$meta_with_args": ["arg1", "arg2"], "meta_key": "meta_value"}
  let args_arr = make_array2(jse_string("arg1"), jse_string("arg2"))
  let expr = jse_object(meta_make_object2(
    "$meta_with_args", jse_array(args_arr),
    "meta_key", jse_string("meta_value")
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="2")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }
}

// --- Meta Lifecycle Tests ---

test "meta cleared after functor" {
  let engine = create_engine_with_meta_functors()
  // First call with metadata
  let expr1 = jse_object(meta_make_object2(
    "$get_meta", jse_null(),
    "temp_key", jse_string("temp_value")
  ))
  match Engine::execute(engine, expr1) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="1")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }

  // Second call without metadata - should return empty map
  let expr2 = jse_object(meta_make_object1("$get_meta", jse_null()))
  match Engine::execute(engine, expr2) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="0")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta available during functor execution" {
  let engine = create_engine_with_meta_functors()
  // Clear last_meta
  last_meta.val = Map::new()

  // {"$identity": "return_value", "stored_key": "stored_value"}
  let expr = jse_object(meta_make_object2(
    "$identity", jse_string("return_value"),
    "stored_key", jse_string("stored_value")
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::StringValue(s) => inspect(s, content="return_value")
        _ => abort("Expected StringValue")
      }
    }
    Err(e) => abort(e)
  }

  // Check that last_meta was set
  let meta = last_meta.val
  inspect(meta.length(), content="1")
}

// --- Metadata Value Types Tests ---

test "meta object value" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "config", "config": {"nested": "value", "number": 42}}
  let config_obj = meta_make_object2("nested", jse_string("value"), "number", jse_number(42))
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("config"),
    "config", jse_object(config_obj)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="2")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta list value" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "items", "items": [1, 2, 3]}
  let items_arr = make_array3(jse_number(1), jse_number(2), jse_number(3))
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("items"),
    "items", jse_array(items_arr)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ArrayValue(result) => {
          inspect(result.length(), content="3")
        }
        _ => abort("Expected ArrayValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta null value" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "nullable", "nullable": null}
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("nullable"),
    "nullable", jse_null()
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::NullValue => inspect("null", content="null")
        _ => abort("Expected NullValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta boolean true" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "flag", "flag": true}
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("flag"),
    "flag", jse_bool(true)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::BoolValue(b) => inspect(b, content="true")
        _ => abort("Expected BoolValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta boolean false" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "flag", "flag": false}
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("flag"),
    "flag", jse_bool(false)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::BoolValue(b) => inspect(b, content="false")
        _ => abort("Expected BoolValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta nested list value" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "nested", "nested": [[1, 2], [3, 4]]}
  let inner1 = make_array2(jse_number(1), jse_number(2))
  let inner2 = make_array2(jse_number(3), jse_number(4))
  let nested_arr = make_array2(jse_array(inner1), jse_array(inner2))
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("nested"),
    "nested", jse_array(nested_arr)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ArrayValue(result) => {
          inspect(result.length(), content="2")
        }
        _ => abort("Expected ArrayValue")
      }
    }
    Err(e) => abort(e)
  }
}

test "meta complex object" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "complex", "complex": {"level1": {"level2": "deep_value"}, "array": [1, 2, 3]}}
  let level1_obj = meta_make_object1("level2", jse_string("deep_value"))
  let arr = make_array3(jse_number(1), jse_number(2), jse_number(3))
  let complex_obj = meta_make_object2(
    "level1", jse_object(level1_obj),
    "array", jse_array(arr)
  )
  let expr = jse_object(meta_make_object2(
    "$get_meta_key", jse_string("complex"),
    "complex", jse_object(complex_obj)
  ))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::ObjectValue(result) => {
          inspect(result.length(), content="2")
        }
        _ => abort("Expected ObjectValue")
      }
    }
    Err(e) => abort(e)
  }
}

// --- Missing Metadata Tests ---

test "meta missing key" {
  let engine = create_engine_with_meta_functors()
  // {"$get_meta_key": "nonexistent"}
  let expr = jse_object(meta_make_object1("$get_meta_key", jse_string("nonexistent")))
  match Engine::execute(engine, expr) {
    Ok(v) => {
      match v {
        JseValue::NullValue => inspect("null", content="null")
        _ => abort("Expected NullValue")
      }
    }
    Err(e) => abort(e)
  }
}
