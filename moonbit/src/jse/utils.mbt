/// Utility functors for JSE.

/// Utility functors map
pub fn utils_functors() -> Map[String, Functor] {
  let m = Map::new()
  let mut m2 = map_put(m, "$not", not)
  m2 = map_put(m2, "$list?", list_p)
  m2 = map_put(m2, "$map?", map_p)
  m2 = map_put(m2, "$null?", null_p)
  m2 = map_put(m2, "$get", get)
  m2 = map_put(m2, "$set", set_fn)
  m2 = map_put(m2, "$del", del)
  m2 = map_put(m2, "$conj", conj)
  m2 = map_put(m2, "$and", and_fn)
  m2 = map_put(m2, "$or", or_fn)
  m2
}

fn not(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Ok(JseValue::Bool(true))
  }
  let b = to_bool(args[0])
  Ok(to_json_bool(!b))
}

fn list_p(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Ok(JseValue::Bool(false))
  }
  match args[0] {
    JseValue::Array(_) => Ok(JseValue::Bool(true))
    _ => Ok(JseValue::Bool(false))
  }
}

fn map_p(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Ok(JseValue::Bool(false))
  }
  match args[0] {
    JseValue::Object(_) => Ok(JseValue::Bool(true))
    _ => Ok(JseValue::Bool(false))
  }
}

fn null_p(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Ok(JseValue::Bool(true))
  }
  match args[0] {
    Null => Ok(JseValue::Bool(true))
    _ => Ok(JseValue::Bool(false))
  }
}

fn get(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 2 {
    return Err("$get requires at least two arguments")
  }

  match args[0] {
    Object(obj) => {
      match args[1] {
        String(key) => {
          match obj.get(key) {
            Some(v) => Ok(v)
            None => Ok(Null)
          }
        }
        _ => Err("$get second argument must be a string")
      }
    }
    _ => Err("$get first argument must be an object")
  }
}

fn set_fn(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 3 {
    return Err("$set requires at least three arguments")
  }

  match args[0] {
    JseValue::Object(obj) => {
      match args[1] {
        JseValue::String(key) => {
          // Note: In MoonBit, Map is immutable, so we need to create a new map
          let result = Map::new()
          let mut result2 = result
          let keys = obj.keys()
          for k in keys {
            match obj.get(k) {
              Some(v) => result2 = map_put(result2, k, v)
              None => ()
            }
          }
          result2 = map_put(result2, key, args[2])
          Ok(JseValue::Object(result2))
        }
        _ => Err("$set second argument must be a string")
      }
    }
    _ => Err("$set first argument must be an object")
  }
}

fn del(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 2 {
    return Err("$del requires at least two arguments")
  }

  match args[0] {
    Object(obj) => {
      match args[1] {
        String(key) => {
          // Note: In MoonBit, Map is immutable, so we need to create a new map
          let result = Map::new()
          let mut result2 = result
          let keys = obj.keys()
          for k in keys {
            if k != key {
              match obj.get(k) {
                Some(v) => result2 = map_put(result2, k, v)
                None => ()
              }
            }
          }
          Ok(Object(result2))
        }
        _ => Err("$del second argument must be a string")
      }
    }
    _ => Err("$del first argument must be an object")
  }
}

fn conj(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 3 {
    return Err("$conj requires at least three arguments")
  }

  match args[0] {
    Object(obj) => {
      match args[1] {
        String(key) => {
          // Note: In MoonBit, Map is immutable, so we need to create a new map
          let result = Map::new()
          let mut result2 = result
          let keys = obj.keys()
          for k in keys {
            match obj.get(k) {
              Some(v) => result2 = map_put(result2, k, v)
              None => ()
            }
          }
          result2 = map_put(result2, key, args[2])
          Ok(Object(result2))
        }
        _ => Err("$conj second argument must be a string")
      }
    }
    _ => Err("$conj first argument must be an object")
  }
}

fn and_fn(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  for v in args {
    if !to_bool(v) {
      return Ok(JseValue::Bool(false))
    }
  }
  Ok(JseValue::Bool(true))
}

fn or_fn(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  for v in args {
    if to_bool(v) {
      return Ok(JseValue::Bool(true))
    }
  }
  Ok(JseValue::Bool(false))
}

/// Convert JSON value to boolean
fn to_bool(v : JseValue) -> Bool {
  match v {
    JseValue::Bool(b) => b
    JseValue::Null => false
    _ => true
  }
}

/// Convert bool to JSON boolean
fn to_json_bool(b : Bool) -> JseValue {
  if b { JseValue::Bool(true) } else { JseValue::Bool(false) }
}
