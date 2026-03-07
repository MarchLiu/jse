/// Minimal JSON Structural Expression (JSE) engine in MoonBit.
///
/// Following the design in docs/regular.md:
/// - AST-based evaluation (not direct evaluation)
/// - env.eval() and ast.apply() mutual support
/// - Two-env pattern for static scoping

/// Engine executes JSE expressions
pub struct Engine {
  env : Env
  parser : Parser
}

/// Create a new engine with the given environment
pub fn engine_new(env_val : Env) -> Engine {
  { env: env_val, parser: parser_new(env_val) }
}

/// Create a new engine with minimal environment (no functors loaded)
pub fn with_env() -> Engine {
  let env_val = new()
  engine_new(env_val)
}

/// Create a new engine with default functors loaded
/// Includes: builtin + utils
pub fn with_default_env() -> Engine {
  let env_val = new()
  load(env_val, builtin_functors())
  load(env_val, utils_functors())
  engine_new(env_val)
}

/// Execute a JSE expression
pub fn Engine::execute(self : Engine, expr : JseValue) -> Result[JseValue, String] {
  // Parse into AST
  match Parser::parse(self.parser, expr) {
    Ok(node) => {
      // Evaluate using environment
      match ast_node_enum_apply(node, self.env) {
        Ok(v) => Ok(v)
        Err(e) => {
          match e {
            AstError::SymbolNotFound(s) => Err("Symbol not found: " + s)
            AstError::TypeError(s) => Err("Type error: " + s)
            AstError::ArityError(s) => Err("Arity error: " + s)
            AstError::EvalError(s) => Err("Eval error: " + s)
          }
        }
      }
    }
    Err(e) => {
      match e {
        AstError::SymbolNotFound(s) => Err("Symbol not found: " + s)
        AstError::TypeError(s) => Err("Type error: " + s)
        AstError::ArityError(s) => Err("Arity error: " + s)
        AstError::EvalError(s) => Err("Eval error: " + s)
      }
    }
  }
}

/// Get the engine's environment
pub fn Engine::get_env(self : Engine) -> Env {
  self.env
}

/// Evaluate an expression with no external environment
/// This is the simplified API for basic usage
pub fn eval(expr : JseValue) -> JseValue {
  match with_default_env().execute(expr) {
    Ok(v) => v
    Err(_) => JseValue::NullValue
  }
}
