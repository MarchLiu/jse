/// Minimal JSON Structural Expression (JSE) engine in MoonBit.
///
/// Supported features:
/// - literals: Null / Bool / Number / String / Array / Object
/// - logical operators: $and / $or / $not
/// - $quote and $expr
/// $pattern / $query are not yet implemented in this minimal version.

fn is_symbol(s : String) -> Bool {
  s.has_prefix("$") && !s.has_prefix("$$")
}

fn get_s_expr_key(obj : Map[String, Json]) -> String? {
  let mut found : String? = None
  for entry in obj {
    let (k, _) = entry
    if is_symbol(k) {
      match found {
        Some(_) => return None
        None => found = Some(k)
      }
    }
  }
  found
}

/// Evaluate a JSE expression with no external environment.
pub fn eval(expr : Json) -> Json {
  match expr {
    Null | True | False | Number(_, ..) | String(_) => expr

    Array(arr) => {
      let out = Array::new()
      for v in arr {
        out.push(eval(v))
      }
      Json::array(out)
    }

    Object(obj) => {
      match get_s_expr_key(obj) {
        Some(sym) => {
          let tail = obj.get(sym).unwrap()
          let args = Array::new()
          match tail {
            Array(arr) => for v in arr { args.push(v) }
            _ => args.push(tail)
          }
          eval_s_expr(sym, args)
        }
        None => Json::object(obj)
      }
    }
  }
}

fn to_bool(v : Json) -> Bool {
  match v {
    True => true
    False | Null => false
    _ => true
  }
}

fn eval_s_expr(sym : String, args : Array[Json]) -> Json {
  if sym == "$quote" {
    match args.get(0) {
      Some(v) => v
      None => "".to_json()
    }
  } else {
    let evaled = Array::new()
    for a in args {
      evaled.push(eval(a))
    }

    match sym {
      "$and" => {
        let mut res = true
        for v in evaled {
          if !to_bool(v) {
            res = false
            break
          }
        }
        res.to_json()
      }

      "$or" => {
        let mut res = false
        for v in evaled {
          if to_bool(v) {
            res = true
            break
          }
        }
        res.to_json()
      }

      "$not" => {
        let b = match evaled.get(0) {
          Some(v) => to_bool(v)
          None => false
        }
        (!b).to_json()
      }

      "$expr" => match evaled.get(0) {
        Some(v) => v
        None => "".to_json()
      }

      _ => "".to_json()
    }
  }
}

