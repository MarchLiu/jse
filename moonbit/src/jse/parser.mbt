/// Parser converts JSON values into AST nodes.

/// Parser for converting JSON to AST nodes
pub struct Parser {
  env : Env
}

/// Create a new parser with the given environment
pub fn parser_new(env : Env) -> Parser {
  { env }
}

/// Parse a JSON value into an AST node
pub fn Parser::parse(self : Parser, value : JseValue) -> Result[AstNodeEnum, AstError] {
  match value {
    JseValue::Null | JseValue::Bool(_) | JseValue::Number(_) | JseValue::String(_) => {
      Ok(AstNodeEnum::Literal(literal_new(value, self.env)))
    }

    JseValue::Array(arr) => {
      Parser::parse_array(self, arr)
    }

    JseValue::Object(obj) => {
      Parser::parse_object(self, obj)
    }
  }
}

fn Parser::parse_array(self : Parser, arr : Array[JseValue]) -> Result[AstNodeEnum, AstError] {
  let elements = Array::new()
  let mut elements2 = elements
  for elem in arr {
    match Parser::parse(self, elem) {
      Ok(node) => elements2 = array_push(elements2, node)
      Err(e) => return Err(e)
    }
  }
  Ok(AstNodeEnum::Array(array_new(elements2, self.env)))
}

fn Parser::parse_object(self : Parser, obj : Map[String, JseValue]) -> Result[AstNodeEnum, AstError] {
  // Check for object expression (single key starting with $)
  match get_s_expr_key(obj) {
    Some(sym) => {
      let value = match obj.get(sym) {
        Some(v) => v
        None => JseValue::Null
      }

      match Parser::parse(self, value) {
        Ok(node) => Ok(AstNodeEnum::ObjectExpression(object_expression_new(sym, node, self.env)))
        Err(e) => Err(e)
      }
    }
    None => {
      // Regular object
      let dict = Map::new()
      let mut dict2 = dict
      let keys = obj.keys()
      for key in keys {
        match obj.get(key) {
          Some(v) => {
            match Parser::parse(self, v) {
              Ok(node) => dict2 = map_put(dict2, key, node)
              Err(e) => return Err(e)
            }
          }
          None => ()
        }
      }
      Ok(AstNodeEnum::Object(object_new(dict2, self.env)))
    }
  }
}

/// Get the S-expression key from an object
/// Returns Some(key) if object has a single key starting with $
fn get_s_expr_key(obj : Map[String, JseValue]) -> String? {
  let keys = obj.keys()
  let keys_arr = keys.to_array()

  if keys_arr.length() == 1 {
    let key = keys_arr[0]
    if key.has_prefix("$") {
      Some(key)
    } else {
      None
    }
  } else {
    None
  }
}
