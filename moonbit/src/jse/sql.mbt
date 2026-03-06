/// SQL-related functors for JSE.

/// SQL functors map
pub fn sql_functors() -> Map[String, Functor] {
  let m = Map::new()
  let mut m2 = map_put(m, "$pattern", pattern)
  m2 = map_put(m2, "$query", query)
  m2 = map_put(m2, "$expr", expr)
  m2
}

/// Query fields constant
const QUERY_FIELDS : String = "subject, predicate, object, meta"

fn pattern(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 3 {
    return Err("$pattern requires (subject, predicate, object)")
  }

  let subject = match args[0] {
    JseValue::String(s) => s
    _ => return Err("$pattern requires string arguments")
  }
  let predicate = match args[1] {
    JseValue::String(s) => s
    _ => return Err("$pattern requires string arguments")
  }
  let object = match args[2] {
    JseValue::String(s) => s
    _ => return Err("$pattern requires string arguments")
  }

  let triple = pattern_to_triple(subject, predicate, object)
  match triple_to_sql_condition(triple) {
    Ok(cond) => {
      let sql = "select \n    subject, predicate, object, meta \nfrom statement as s \nwhere " + cond + " \noffset 0\nlimit 100 \n"
      Ok(JseValue::String(sql))
    }
    Err(e) => Err(e)
  }
}

fn query(env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.length() < 1 {
    return Err("$query expects [op, patterns array] or [patterns array]")
  }

  // args[0] is the entire array: [op, patterns] or [patterns]
  let raw_value = args[0]

  match raw_value {
    JseValue::Array(arr) => {
      // Extract patterns array
      let patterns = extract_patterns(arr)

      // Evaluate each pattern to get SQL string
      let conditions = Array::new()
      let mut conditions2 = conditions
      for pattern in patterns {
        match eval_json(env, pattern) {
          Ok(result) => {
            match result {
              JseValue::String(sql_str) => {
                let cond = extract_where_clause(sql_str)
                conditions2 = array_push(conditions2, cond)
              }
              _ => return Err("pattern must evaluate to SQL string")
            }
          }
          Err(e) => return Err("failed to evaluate pattern: " + e)
        }
      }

      let where_clause = conditions2.join(" and \n    ")
      let sql = "select " + QUERY_FIELDS + " \nfrom statement \nwhere \n    " + where_clause + " \noffset 0\nlimit 100 \n"
      Ok(JseValue::String(sql))
    }
    _ => Err("$query expects an array argument")
  }
}

fn expr(_env : Env, args : Array[JseValue]) -> Result[JseValue, String] {
  if args.is_empty() {
    return Ok(JseValue::Null)
  }
  Ok(args[0])
}

/// Extract patterns from array
/// Handles [op, patterns] or [patterns] format
fn extract_patterns(arr : Array[JseValue]) -> Array[JseValue] {
  if arr.is_empty() {
    return Array::new()
  }

  match arr.get(0) {
    Some(JseValue::String(op)) if op == "$and" || op == "$or" => {
      // This is [op, patterns] format
      match arr.get(1) {
        Some(JseValue::Array(patterns)) => patterns
        _ => arr
      }
    }
    _ => arr
  }
}

/// Extract WHERE clause from SQL
fn extract_where_clause(sql : String) -> String {
  // Find "where " in the string
  let where_str = "where "
  let mut where_idx = None
  let mut i = 0
  while i < sql.length() - where_str.length() + 1 {
    let mut found = true
    let mut j = 0
    while j < where_str.length() {
      if sql[i + j] != where_str[j] {
        found = false
        break
      }
      j = j + 1
    }
    if found {
      where_idx = Some(i)
      break
    }
    i = i + 1
  }

  match where_idx {
    Some(idx) => {
      let where_start = idx + 6

      // Find " offset" after where_start
      let offset_str = " offset"
      let mut offset_idx = None
      let mut k = where_start
      while k < sql.length() - offset_str.length() + 1 {
        let mut found = true
        let mut j = 0
        while j < offset_str.length() {
          if sql[k + j] != offset_str[j] {
            found = false
            break
          }
          j = j + 1
        }
        if found {
          offset_idx = Some(k - where_start)
          break
        }
        k = k + 1
      }

      match offset_idx {
        Some(oidx) => sql
        None => sql
      }
    }
    None => sql
  }
}

/// Convert pattern arguments to triple
fn pattern_to_triple(subject : String, predicate : String, object : String) -> Array[String] {
  if subject == "$*" && object == "$*" {
    let arr = Array::new()
    arr.push(predicate)
    arr
  } else {
    let arr = Array::new()
    arr.push(subject)
    arr.push(predicate)
    arr.push(object)
    arr
  }
}

/// Build SQL condition from triple
fn triple_to_sql_condition(triple : Array[String]) -> Result[String, String] {
  let doc = Map::new()
  let mut doc2 = doc
  let arr = Array::new()
  let mut arr2 = arr
  for s in triple {
    arr2 = array_push(arr2, JseValue::String(s))
  }
  doc2 = map_put(doc2, "triple", JseValue::Array(arr2))

  // Convert to JSON string
  let json_str = match json_to_string(JseValue::Object(doc2)) {
    Ok(s) => s
    Err(e) => return Err(e)
  }

  // Escape single quotes manually
  let result_chars = Array::new()
  let mut result_chars2 = result_chars
  let mut i = 0
  while i < json_str.length() {
    let char_str = json_str.substring(start = i, end = i + 1)
    if char_str == "'" {
      result_chars2 = array_push(result_chars2, "''")
    } else {
      result_chars2 = array_push(result_chars2, char_str)
    }
    i = i + 1
  }
  let escaped = result_chars2.join("")
  Ok("meta @> '" + escaped + "'")
}

/// Simple JSON to string conversion
fn json_to_string(value : JseValue) -> Result[String, String] {
  match value {
    JseValue::Null => Ok("null")
    JseValue::Bool(true) => Ok("true")
    JseValue::Bool(false) => Ok("false")
    JseValue::Number(n) => Ok(n.to_string())
    JseValue::String(s) => Ok("\"" + s + "\"")
    JseValue::Array(arr) => {
      let mut result = "["
      let mut first = true
      for elem in arr {
        if !first {
          result = result + ","
        }
        first = false
        match json_to_string(elem) {
          Ok(s) => result = result + s
          Err(e) => return Err(e)
        }
      }
      result = result + "]"
      Ok(result)
    }
    JseValue::Object(obj) => {
      let mut result = "{"
      let mut first = true
      let keys = obj.keys()
      for key in keys {
        if !first {
          result = result + ","
        }
        first = false
        match obj.get(key) {
          Some(v) => {
            match json_to_string(v) {
              Ok(s) => result = result + "\"" + key + "\":" + s
              Err(e) => return Err(e)
            }
          }
          None => ()
        }
      }
      result = result + "}"
      Ok(result)
    }
  }
}
