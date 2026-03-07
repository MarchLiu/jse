/// Test file to verify the JseValue enum refactor works correctly.
///
/// This demonstrates that after renaming enum variants with "Value" suffix,
/// we can now create JseValue instances and write tests.

pub fn main {
  println("Testing JseValue enum refactor...")
  println("=")

  // Test 1: Create and match NullValue
  test_null_value()

  // Test 2: Create and match BoolValue
  test_bool_value()

  // Test 3: Create and match NumberValue
  test_number_value()

  // Test 4: Create and match StringValue
  test_string_value()

  // Test 5: Create and match ArrayValue
  test_array_value()

  // Test 6: Create and match ObjectValue
  test_object_value()

  // Test 7: Test with JSE engine
  test_engine_execution()

  println("=")
  println("All tests passed!")
}

/// Test NullValue creation and pattern matching
fn test_null_value() -> Unit {
  let null_val = JseValue::NullValue
  let result = match null_val {
    JseValue::NullValue => "pass"
    _ => "fail"
  }
  assert_eq(result, "pass")
  println("✓ NullValue test passed")
}

/// Test BoolValue creation and pattern matching
fn test_bool_value() -> Unit {
  let true_val = JseValue::BoolValue(true)
  let false_val = JseValue::BoolValue(false)

  let result1 = match true_val {
    JseValue::BoolValue(b) if b => "pass"
    _ => "fail"
  }
  assert_eq(result1, "pass")

  let result2 = match false_val {
    JseValue::BoolValue(b) if !b => "pass"
    _ => "fail"
  }
  assert_eq(result2, "pass")

  println("✓ BoolValue test passed")
}

/// Test NumberValue creation and pattern matching
fn test_number_value() -> Unit {
  let num_val = JseValue::NumberValue(42)

  let result = match num_val {
    JseValue::NumberValue(n) if n == 42 => "pass"
    _ => "fail"
  }
  assert_eq(result, "pass")

  println("✓ NumberValue test passed")
}

/// Test StringValue creation and pattern matching
fn test_string_value() -> Unit {
  let str_val = JseValue::StringValue("hello")

  let result = match str_val {
    JseValue::StringValue(s) if s == "hello" => "pass"
    _ => "fail"
  }
  assert_eq(result, "pass")

  println("✓ StringValue test passed")
}

/// Test ArrayValue creation and pattern matching
fn test_array_value() -> Unit {
  let arr = Array::new()
  let mut arr2 = array_push(arr, JseValue::NumberValue(1))
  arr2 = array_push(arr2, JseValue::NumberValue(2))
  arr2 = array_push(arr2, JseValue::NumberValue(3))
  let arr_val = JseValue::ArrayValue(arr2)

  let result = match arr_val {
    JseValue::ArrayValue(a) => {
      if a.length() == 3 { "pass" } else { "fail" }
    }
    _ => "fail"
  }
  assert_eq(result, "pass")

  println("✓ ArrayValue test passed")
}

/// Test ObjectValue creation and pattern matching
fn test_object_value() -> Unit {
  let obj = Map::new()
  let mut obj2 = map_put(obj, "key", JseValue::StringValue("value"))
  obj2 = map_put(obj2, "number", JseValue::NumberValue(42))
  let obj_val = JseValue::ObjectValue(obj2)

  let result = match obj_val {
    JseValue::ObjectValue(o) => {
      let keys = o.keys()
      let keys_arr = keys.to_array()
      if keys_arr.length() == 2 { "pass" } else { "fail" }
    }
    _ => "fail"
  }
  assert_eq(result, "pass")

  println("✓ ObjectValue test passed")
}

/// Test JSE engine execution with refactored JseValue
fn test_engine_execution() -> Unit {
  let engine = jse::with_default_env()

  // Test $not functor
  match execute(engine, JseValue::BoolValue(true)) {
    Ok(v) => {
      let result = match v {
        JseValue::BoolValue(b) => b
        _ => false
      }
      assert_eq(result, true)
    }
    Err(e) => {
      println("Error in engine test: " + e)
      assert_true(false)
    }
  }

  // Test array evaluation
  let arr = Array::new()
  let mut arr2 = array_push(arr, JseValue::StringValue("$and"))
  arr2 = array_push(arr2, JseValue::BoolValue(true))
  arr2 = array_push(arr2, JseValue::BoolValue(true))

  match execute(engine, JseValue::ArrayValue(arr2)) {
    Ok(v) => {
      let result = match v {
        JseValue::BoolValue(b) => b
        _ => false
      }
      assert_eq(result, true)
    }
    Err(e) => {
      println("Error in array test: " + e)
      assert_true(false)
    }
  }

  println("✓ Engine execution test passed")
}

/// Helper function for array push
pub fn[T] array_push(arr : Array[T], elem : T) -> Array[T] {
  let mut result = arr
  result.push(elem)
  result
}

/// Helper function for map put
pub fn[K : Eq + Hash, V] map_put(m : Map[K, V], key : K, value : V) -> Map[K, V] {
  let mut result = m
  result[key] = value
  result
}

/// Assert equality
fn assert_eq[T : Eq + Show](a : T, b : T) -> Unit {
  if a != b {
    println("Assertion failed: expected " + b.to_string() + ", got " + a.to_string())
    panic("assert_eq failed")
  }
}

/// Assert condition is true
fn assert_true(b : Bool) -> Unit {
  if !b {
    println("Assertion failed: expected true, got false")
    panic("assert_true failed")
  }
}
