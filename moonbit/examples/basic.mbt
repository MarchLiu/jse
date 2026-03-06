/// Basic JSE usage example
///
/// This example demonstrates how to use the JSE engine
/// to evaluate JSON Structural Expressions.

pub fn main {
  let engine = with_default_env()

  // Test 1: Number expression
  match execute(engine, JseValue::Number(42)) {
    Ok(result) => println("Number 42 evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 2: Boolean expression
  match execute(engine, JseValue::Bool(true)) {
    Ok(result) => println("Boolean true evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 3: String expression
  match execute(engine, JseValue::String("hello")) {
    Ok(result) => println("String 'hello' evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 4: Array expression
  let arr = Array::new()
  let mut arr2 = array_push(arr, JseValue::Number(1))
  arr2 = array_push(arr2, JseValue::Number(2))
  arr2 = array_push(arr2, JseValue::Number(3))
  match execute(engine, JseValue::Array(arr2)) {
    Ok(result) => println("Array [1, 2, 3] evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 5: Object expression
  let obj = Map::new()
  let mut obj2 = map_put(obj, "key", JseValue::String("value"))
  match execute(engine, JseValue::Object(obj2)) {
    Ok(result) => println("Object evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }
}

/// Helper function to convert JseValue to string for display
fn jse_value_to_string(value : JseValue) -> String {
  match value {
    JseValue::Null => "null"
    JseValue::Bool(b) => if b { "true" } else { "false" }
    JseValue::Number(n) => n.to_string()
    JseValue::String(s) => "\"" + s + "\""
    JseValue::Array(_) => "[...]"
    JseValue::Object(_) => "{...}"
  }
}
