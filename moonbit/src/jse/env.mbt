/// Environment for JSE execution.
///
/// Follows the design in docs/regular.md:
/// - env has nullable parent field for scope chain lookup
/// - env provides register() method for def/defn
/// - env provides load() method for functor modules
/// - env.eval() delegates to ast.apply() (following jisp pattern)

/// Value type for JSE expressions - local enum to avoid std json complications
pub enum JseValue {
  NullValue
  BoolValue(Bool)
  NumberValue(Int)
  StringValue(String)
  ArrayValue(Array[JseValue])
  ObjectValue(Map[String, JseValue])
}

/// Functor type - a function that takes environment and arguments
pub type Functor = (Env, Array[JseValue]) -> Result[JseValue, String]

/// Environment for JSE execution with scope chaining
pub struct Env {
  parent : Env?
  bindings : Map[String, JseValue]
  functors : Map[String, Functor]
}

/// Create a new empty environment
pub fn new() -> Env {
  { parent: None, bindings: Map::new(), functors: Map::new() }
}

/// Create a new environment with a parent (for closures)
pub fn new_with_parent(parent : Env) -> Env {
  { parent: Some(parent), bindings: Map::new(), functors: Map::new() }
}

/// Get parent environment
pub fn get_parent(env : Env) -> Env? {
  env.parent
}

/// Resolve symbol to value by searching up the scope chain
pub fn resolve(env : Env, symbol : String) -> JseValue? {
  match env.bindings.get(symbol) {
    Some(v) => Some(v)
    None => {
      match env.parent {
        Some(p) => resolve(p, symbol)
        None => None
      }
    }
  }
}

/// Resolve functor from the environment chain
pub fn resolve_functor(env : Env, name : String) -> Functor? {
  match env.functors.get(name) {
    Some(f) => Some(f)
    None => {
      match env.parent {
        Some(p) => resolve_functor(p, name)
        None => None
      }
    }
  }
}

/// Register a new symbol binding in the current environment
/// Throws if symbol already exists in current scope
pub fn register(env : Env, name : String, value : JseValue) -> Result[Unit, String] {
  match env.bindings.get(name) {
    Some(_) => Err("Symbol '" + name + "' already exists in current scope")
    None => {
      env.bindings[name] = value
      Ok(())
    }
  }
}

/// Set a symbol binding, overwriting if exists
pub fn set(env : Env, name : String, value : JseValue) -> Unit {
  env.bindings[name] = value
}

/// Check if symbol exists in current or parent scopes
pub fn exists(env : Env, name : String) -> Bool {
  match env.bindings.get(name) {
    Some(_) => true
    None => {
      match env.parent {
        Some(p) => exists(p, name)
        None => false
      }
    }
  }
}

/// Register a functor in the current environment
pub fn register_functor(env : Env, name : String, functor : Functor) -> Unit {
  env.functors[name] = functor
}

/// Load a functor module into this environment
pub fn load(env : Env, functors_mod : Map[String, Functor]) -> Unit {
  let keys = functors_mod.keys()
  for key in keys {
    match functors_mod.get(key) {
      Some(functor) => env.functors[key] = functor
      None => ()
    }
  }
}

/// Apply a functor with evaluated values
pub fn apply_functor(env : Env, name : String, args : Array[JseValue]) -> Result[JseValue, String] {
  match resolve_functor(env, name) {
    Some(f) => f(env, args)
    None => Err("Unknown symbol: " + name)
  }
}

/// Evaluate a raw JSON value
pub fn eval_json(env : Env, expr : JseValue) -> Result[JseValue, String] {
  // For primitive values, return as-is
  match expr {
    JseValue::NullValue | JseValue::BoolValue(_) | JseValue::NumberValue(_) | JseValue::StringValue(_) => Ok(expr)
    _ => {
      // For complex values, we need to parse and evaluate
      // This will be implemented with the parser
      Err("eval_json needs parser implementation")
    }
  }
}
