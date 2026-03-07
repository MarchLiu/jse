/// Basic JSE usage example
///
/// This example demonstrates how to use the JSE engine
/// to evaluate JSON Structural Expressions.

pub fn main {
  let engine = with_default_env()

  // Test 1: Number expression
  match execute(engine, JseValue::NumberValue(42)) {
    Ok(result) => println("Number 42 evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 2: Boolean expression
  match execute(engine, JseValue::BoolValue(true)) {
    Ok(result) => println("Boolean true evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 3: String expression
  match execute(engine, JseValue::StringValue("hello")) {
    Ok(result) => println("String 'hello' evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 4: Array expression
  let arr = Array::new()
  let mut arr2 = array_push(arr, JseValue::NumberValue(1))
  arr2 = array_push(arr2, JseValue::NumberValue(2))
  arr2 = array_push(arr2, JseValue::NumberValue(3))
  match execute(engine, JseValue::ArrayValue(arr2)) {
    Ok(result) => println("Array [1, 2, 3] evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }

  // Test 5: Object expression
  let obj = Map::new()
  let mut obj2 = map_put(obj, "key", JseValue::StringValue("value"))
  match execute(engine, JseValue::ObjectValue(obj2)) {
    Ok(result) => println("Object evaluated to: " + jse_value_to_string(result))
    Err(e) => println("Error: " + e)
  }
}

/// Helper function to convert JseValue to string for display
fn jse_value_to_string(value : JseValue) -> String {
  match value {
    JseValue::NullValue => "null"
    JseValue::BoolValue(b) => if b { "true" } else { "false" }
    JseValue::NumberValue(n) => n.to_string()
    JseValue::StringValue(s) => "\"" + s + "\""
    JseValue::ArrayValue(_) => "[...]"
    JseValue::ObjectValue(_) => "{...}"
  }
}
