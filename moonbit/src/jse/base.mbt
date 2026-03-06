/// Base AST node trait for JSE.
///
/// Following the design in docs/regular.md:
/// - AST nodes contain env (passed during construction)
/// - AST nodes have apply() method for execution
/// - Two-env pattern enables static scoping

/// Error type for AST operations
pub enum AstError {
  SymbolNotFound(String)
  TypeError(String)
  ArityError(String)
  EvalError(String)
}

/// Base trait for all AST nodes
pub trait AstNode {
  /// Get the construct-time environment (for closures)
  get_env() -> Env

  /// Execute this node with call-time environment
  apply(Env) -> Result[JseValue, AstError]

  /// Convert this node to its JSON representation
  to_json() -> JseValue

  /// Check if this node is a symbol with the given name
  is_symbol_named(String) -> Bool
}

/// Enum that wraps all AST node types (since MoonBit doesn't support trait objects)
pub enum AstNodeEnum {
  Literal(LiteralNode)
  Symbol(SymbolNode)
  Array(ArrayNode)
  Object(ObjectNode)
  ObjectExpression(ObjectExpressionNode)
  Quote(QuoteNode)
  Lambda(LambdaNode)
}
