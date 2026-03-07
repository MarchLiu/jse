/// Concrete AST node implementations.
///
/// Simplified for MoonBit compatibility

/// Literal value node
pub struct LiteralNode {
  value : JseValue
  env : Env
}

pub fn literal_new(value : JseValue, env : Env) -> LiteralNode {
  { value, env }
}

pub fn literal_get_env(node : LiteralNode) -> Env {
  node.env
}

pub fn literal_apply(node : LiteralNode, _env : Env) -> Result[JseValue, AstError] {
  Ok(node.value)
}

pub fn literal_to_json(node : LiteralNode) -> JseValue {
  node.value
}

/// Symbol reference node
pub struct SymbolNode {
  name : String
  env : Env
}

pub fn symbol_new(name : String, env : Env) -> SymbolNode {
  { name, env }
}

pub fn symbol_get_env(node : SymbolNode) -> Env {
  node.env
}

pub fn symbol_apply(node : SymbolNode, env : Env) -> Result[JseValue, AstError] {
  match resolve(env, node.name) {
    Some(v) => Ok(v)
    None => Err(AstError::SymbolNotFound(node.name))
  }
}

pub fn symbol_to_json(node : SymbolNode) -> JseValue {
  JseValue::StringValue(node.name)
}

pub fn symbol_is_symbol_named(node : SymbolNode, name : String) -> Bool {
  node.name == name
}

pub fn symbol_name(node : SymbolNode) -> String {
  node.name
}

/// Array node (function call or regular array)
pub struct ArrayNode {
  elements : Array[AstNodeEnum]
  env : Env
}

pub fn array_new(elements : Array[AstNodeEnum], env : Env) -> ArrayNode {
  { elements, env }
}

pub fn array_is_symbol(s : String) -> Bool {
  s.has_prefix("$") && !s.has_prefix("$$") && s != "$*"
}

pub fn array_get_env(node : ArrayNode) -> Env {
  node.env
}

pub fn array_apply(node : ArrayNode, env : Env) -> Result[JseValue, AstError] {
  if node.elements.is_empty() {
    return Ok(JseValue::ArrayValue(Array::new()))
  }

  let first = node.elements[0]
  match first {
    AstNodeEnum::Symbol(s) => {
      let name = symbol_name(s)
      if array_is_symbol(name) {
        array_apply_function_call(node, env, name)
      } else {
        array_apply_regular(node, env)
      }
    }
    _ => array_apply_regular(node, env)
  }
}

pub fn array_to_json(node : ArrayNode) -> JseValue {
  let arr = Array::new()
  let mut arr2 = arr
  for elem in node.elements {
    arr2 = array_push(arr2, ast_node_enum_to_json(elem))
  }
  JseValue::ArrayValue(arr2)
}

pub fn array_is_symbol_named(node : ArrayNode, name : String) -> Bool {
  match node.elements.get(0) {
    Some(first) => {
      match first {
        AstNodeEnum::Symbol(s) => symbol_is_symbol_named(s, name)
        _ => false
      }
    }
    None => false
  }
}

fn array_apply_function_call(node : ArrayNode, env : Env, symbol : String) -> Result[JseValue, AstError] {
  let rest = array_rest(node)

  // Special forms that don't evaluate arguments
  if symbol == "$quote" {
    let args = Array::new()
    let mut args2 = args
    for elem in rest {
      args2 = array_push(args2, ast_node_enum_to_json(elem))
    }
    array_apply_functor(env, symbol, args2)
  } else {
    // Regular functors - evaluate arguments first
    let evaluated = Array::new()
    let mut evaluated2 = evaluated
    for elem in rest {
      match ast_node_enum_apply(elem, env) {
        Ok(v) => evaluated2 = array_push(evaluated2, v)
        Err(e) => return Err(e)
      }
    }
    array_apply_functor(env, symbol, evaluated2)
  }
}

fn array_apply_regular(node : ArrayNode, env : Env) -> Result[JseValue, AstError] {
  let result = Array::new()
  let mut result2 = result
  for elem in node.elements {
    match ast_node_enum_apply(elem, env) {
      Ok(v) => result2 = array_push(result2, v)
      Err(e) => return Err(e)
    }
  }
  Ok(JseValue::ArrayValue(result2))
}

fn array_rest(node : ArrayNode) -> Array[AstNodeEnum] {
  if node.elements.length() <= 1 {
    Array::new()
  } else {
    let result = Array::new()
    let mut result2 = result
    let mut i = 1
    while i < node.elements.length() {
      result2 = array_push(result2, node.elements[i])
      i = i + 1
    }
    result2
  }
}

fn array_apply_functor(env : Env, symbol : String, args : Array[JseValue]) -> Result[JseValue, AstError] {
  match apply_functor(env, symbol, args) {
    Ok(v) => Ok(v)
    Err(e) => Err(AstError::EvalError(e))
  }
}

/// Object node (key-value pairs)
pub struct ObjectNode {
  dict : Map[String, AstNodeEnum]
  env : Env
}

pub fn object_new(dict : Map[String, AstNodeEnum], env : Env) -> ObjectNode {
  { dict, env }
}

pub fn object_get_env(node : ObjectNode) -> Env {
  node.env
}

pub fn object_apply(node : ObjectNode, env : Env) -> Result[JseValue, AstError] {
  let result = Map::new()
  let mut result2 = result
  let keys = node.dict.keys()
  for key in keys {
    match node.dict.get(key) {
      Some(n) => {
        match ast_node_enum_apply(n, env) {
          Ok(v) => result2 = map_put(result2, key, v)
          Err(e) => return Err(e)
        }
      }
      None => ()
    }
  }
  Ok(JseValue::ObjectValue(result2))
}

pub fn object_to_json(node : ObjectNode) -> JseValue {
  let result = Map::new()
  let mut result2 = result
  let keys = node.dict.keys()
  for key in keys {
    match node.dict.get(key) {
      Some(n) => result2 = map_put(result2, key, ast_node_enum_to_json(n))
      None => ()
    }
  }
  JseValue::ObjectValue(result2)
}

/// Object expression node ({"$operator": value})
pub struct ObjectExpressionNode {
  operator : String
  value : AstNodeEnum
  env : Env
}

pub fn object_expression_new(operator : String, value : AstNodeEnum, env : Env) -> ObjectExpressionNode {
  { operator, value, env }
}

pub fn object_expression_get_env(node : ObjectExpressionNode) -> Env {
  node.env
}

pub fn object_expression_apply(node : ObjectExpressionNode, env : Env) -> Result[JseValue, AstError] {
  if node.operator == "$expr" {
    return ast_node_enum_apply(node.value, env)
  }

  if node.operator == "$pattern" || node.operator == "$query" {
    let json_value = ast_node_enum_to_json(node.value)
    let args = Array::new()
    let args2 = array_push(args, json_value)
    return object_expression_apply_functor(env, node.operator, args2)
  }

  match ast_node_enum_apply(node.value, env) {
    Ok(evaluated) => {
      let args = Array::new()
      let args2 = array_push(args, evaluated)
      object_expression_apply_functor(env, node.operator, args2)
    }
    Err(e) => Err(e)
  }
}

pub fn object_expression_to_json(node : ObjectExpressionNode) -> JseValue {
  let obj = Map::new()
  let obj2 = map_put(obj, node.operator, ast_node_enum_to_json(node.value))
  JseValue::ObjectValue(obj2)
}

fn object_expression_apply_functor(env : Env, symbol : String, args : Array[JseValue]) -> Result[JseValue, AstError] {
  match apply_functor(env, symbol, args) {
    Ok(v) => Ok(v)
    Err(e) => Err(AstError::EvalError(e))
  }
}

/// Quote node
pub struct QuoteNode {
  value : AstNodeEnum
  env : Env
}

pub fn quote_new(value : AstNodeEnum, env : Env) -> QuoteNode {
  { value, env }
}

pub fn quote_get_env(node : QuoteNode) -> Env {
  node.env
}

pub fn quote_apply(node : QuoteNode, _env : Env) -> Result[JseValue, AstError] {
  Ok(ast_node_enum_to_json(node.value))
}

pub fn quote_to_json(node : QuoteNode) -> JseValue {
  ast_node_enum_to_json(node.value)
}

/// Lambda node (closure with static scoping)
pub struct LambdaNode {
  params : Array[String]
  body : AstNodeEnum
  closure_env : Env
}

pub fn lambda_new(params : Array[String], body : AstNodeEnum, closure_env : Env) -> LambdaNode {
  { params, body, closure_env }
}

pub fn lambda_get_env(node : LambdaNode) -> Env {
  node.closure_env
}

pub fn lambda_apply(node : LambdaNode, _env : Env) -> Result[JseValue, AstError] {
  let obj = Map::new()
  let mut obj2 = map_put(obj, "__lambda__", JseValue::BoolValue(true))
  let params_array = Array::new()
  let mut params_array2 = params_array
  for param in node.params {
    params_array2 = array_push(params_array2, JseValue::StringValue(param))
  }
  obj2 = map_put(obj2, "params", JseValue::ArrayValue(params_array2))
  obj2 = map_put(obj2, "body", ast_node_enum_to_json(node.body))
  Ok(JseValue::ObjectValue(obj2))
}

pub fn lambda_to_json(_node : LambdaNode) -> JseValue {
  JseValue::StringValue("<lambda>")
}

/// Helper functions for working with AstNodeEnum
pub fn ast_node_enum_get_env(node : AstNodeEnum) -> Env {
  match node {
    AstNodeEnum::Literal(n) => literal_get_env(n)
    AstNodeEnum::Symbol(n) => symbol_get_env(n)
    AstNodeEnum::Array(n) => array_get_env(n)
    AstNodeEnum::Object(n) => object_get_env(n)
    AstNodeEnum::ObjectExpression(n) => object_expression_get_env(n)
    AstNodeEnum::Quote(n) => quote_get_env(n)
    AstNodeEnum::Lambda(n) => lambda_get_env(n)
  }
}

pub fn ast_node_enum_apply(node : AstNodeEnum, env : Env) -> Result[JseValue, AstError] {
  match node {
    AstNodeEnum::Literal(n) => literal_apply(n, env)
    AstNodeEnum::Symbol(n) => symbol_apply(n, env)
    AstNodeEnum::Array(n) => array_apply(n, env)
    AstNodeEnum::Object(n) => object_apply(n, env)
    AstNodeEnum::ObjectExpression(n) => object_expression_apply(n, env)
    AstNodeEnum::Quote(n) => quote_apply(n, env)
    AstNodeEnum::Lambda(n) => lambda_apply(n, env)
  }
}

pub fn ast_node_enum_to_json(node : AstNodeEnum) -> JseValue {
  match node {
    AstNodeEnum::Literal(n) => literal_to_json(n)
    AstNodeEnum::Symbol(n) => symbol_to_json(n)
    AstNodeEnum::Array(n) => array_to_json(n)
    AstNodeEnum::Object(n) => object_to_json(n)
    AstNodeEnum::ObjectExpression(n) => object_expression_to_json(n)
    AstNodeEnum::Quote(n) => quote_to_json(n)
    AstNodeEnum::Lambda(n) => lambda_to_json(n)
  }
}

pub fn ast_node_enum_is_symbol_named(node : AstNodeEnum, name : String) -> Bool {
  match node {
    AstNodeEnum::Literal(_) => false
    AstNodeEnum::Symbol(n) => symbol_is_symbol_named(n, name)
    AstNodeEnum::Array(n) => array_is_symbol_named(n, name)
    AstNodeEnum::Object(_) => false
    AstNodeEnum::ObjectExpression(_) => false
    AstNodeEnum::Quote(_) => false
    AstNodeEnum::Lambda(_) => false
  }
}
