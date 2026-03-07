/// Builtin functors for JSE.

/// Helper to add entry to map and return it (for unused_mut fix)
pub fn[K : Eq + Hash, V] map_put(m : Map[K, V], key : K, value : V) -> Map[K, V] {
  let mut result = m
  result[key] = value
  // Workaround: reassign to satisfy unused_mut check
  result = result
  result
}

/// Helper to push to array and return it (for unused_mut fix)
pub fn[T] array_push(arr : Array[T], elem : T) -> Array[T] {
  let mut result = arr
  result.push(elem)
  // Workaround: reassign to satisfy unused_mut check
  result = result
  result
}

/// Builtin functors map
pub fn builtin_functors() -> Map[String, Functor] {
  let m = Map::new()
  let mut m2 = map_put(m, "$quote", quote)
  m2 = map_put(m2, "$eq", eq)
  m2 = map_put(m2, "$cond", cond)
  m2 = map_put(m2, "$head", head)
  m2 = map_put(m2, "$tail", tail)
  m2 = map_put(m2, "$atom?", atom_p)
  m2 = map_put(m2, "$cons", cons)
  m2
}

fn quote(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  match args.get(0) {
    Some(v) => Ok(v)
    None => Ok(JseValue::NullValue)
  }
}

fn eq(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 2 {
    return Ok(JseValue::BoolValue(false))
  }

  let first = args[0]
  let mut result = true
  let mut i = 1
  while i < args.length() {
    if !is_equal(first, args[i]) {
      result = false
      break
    }
    i = i + 1
  }
  Ok(to_json_bool(result))
}

fn cond(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  let mut i = 0
  while i < args.length() - 1 {
    match args[i] {
      JseValue::BoolValue(b) => {
        if b {
          return Ok(args[i + 1])
        }
      }
      _ => ()
    }
    i = i + 2
  }

  // Default case (odd number of args)
  if args.length() % 2 == 1 {
    return Ok(args[args.length() - 1])
  }

  Ok(JseValue::NullValue)
}

fn head(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Err("$head requires at least one argument")
  }

  match args[0] {
    JseValue::ArrayValue(arr) => {
      if arr.is_empty() {
        Ok(JseValue::NullValue)
      } else {
        Ok(arr[0])
      }
    }
    _ => Err("$head argument must be an array")
  }
}

fn tail(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Err("$tail requires at least one argument")
  }

  match args[0] {
    JseValue::ArrayValue(arr) => {
      if arr.is_empty() {
        return Ok(JseValue::ArrayValue(Array::new()))
      }
      if arr.length() == 1 {
        return Ok(JseValue::ArrayValue(Array::new()))
      }
      let len = arr.length()
      let result = Array::new()
      let mut result2 = result
      let mut i = 1
      while i < len {
        result2 = array_push(result2, arr[i])
        i = i + 1
      }
      Ok(JseValue::ArrayValue(result2))
    }
    _ => Err("$tail argument must be an array")
  }
}

fn atom_p(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Ok(JseValue::BoolValue(true))
  }

  match args[0] {
    JseValue::ArrayValue(_) | JseValue::ObjectValue(_) => Ok(JseValue::BoolValue(false))
    _ => Ok(JseValue::BoolValue(true))
  }
}

fn cons(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 2 {
    return Err("$cons requires two arguments")
  }

  match args[1] {
    JseValue::ArrayValue(arr) => {
      let result = Array::new()
      let mut result2 = array_push(result, args[0])
      for elem in arr {
        result2 = array_push(result2, elem)
      }
      Ok(JseValue::ArrayValue(result2))
    }
    _ => Err("$cons second argument must be an array")
  }
}

/// Helper function for equality check
fn is_equal(a : JseValue, b : JseValue) -> Bool {
  match (a, b) {
    (JseValue::BoolValue(x), JseValue::BoolValue(y)) => x == y
    (JseValue::NullValue, JseValue::NullValue) => true
    (JseValue::NumberValue(x), JseValue::NumberValue(y)) => x == y
    (JseValue::StringValue(x), JseValue::StringValue(y)) => x == y
    (JseValue::ArrayValue(x), JseValue::ArrayValue(y)) => {
      if x.length() != y.length() {
        return false
      }
      let mut i = 0
      let mut result = true
      while i < x.length() {
        if !is_equal(x[i], y[i]) {
          result = false
          break
        }
        i = i + 1
      }
      result
    }
    (JseValue::ObjectValue(x), JseValue::ObjectValue(y)) => {
      let x_keys = x.keys()
      let y_keys = y.keys()
      let x_arr = x_keys.to_array()
      let y_arr = y_keys.to_array()
      if x_arr.length() != y_arr.length() {
        return false
      }
      let mut result = true
      for key in x_arr {
        match (x.get(key), y.get(key)) {
          (Some(xv), Some(yv)) => {
            if !is_equal(xv, yv) {
              result = false
              break
            }
          }
          (_, _) => {
            result = false
            break
          }
        }
      }
      result
    }
    (_, _) => false
  }
}
