//! Concrete AST node implementations.
//!
//! Following Python's ast/nodes.py pattern with Rust traits:

use std::rc::Rc;
use std::cell::RefCell;
use std::collections::HashMap;
use serde_json::{Map, Value};
use crate::env::Env;
use crate::ast::{AstError, Parser};

/// Base trait for all AST nodes
pub trait AstNode {
    /// Get the construct-time environment (for closures)
    fn get_env(&self) -> Rc<RefCell<Env>>;

    /// Execute this node with call-time environment
    fn apply(&self, env: &Rc<RefCell<Env>>) -> Result<Value, AstError>;

    /// Convert this node to its JSON representation
    fn to_json(&self) -> Value;

    /// Check if this node is a symbol with the given name
    fn is_symbol_named(&self, name: &str) -> bool {
        false
    }
}

/// Literal value node (numbers, strings, bool, null)
pub struct LiteralNode {
    value: Value,
    env: Rc<RefCell<Env>>,
}

impl LiteralNode {
    pub fn new(value: Value, env: Rc<RefCell<Env>>) -> Self {
        Self { value, env }
    }
}

impl AstNode for LiteralNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.env)
    }

    fn apply(&self, _env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        Ok(self.value.clone())
    }

    fn to_json(&self) -> Value {
        self.value.clone()
    }
}

/// Symbol reference node (e.g., $x)
pub struct SymbolNode {
    name: String,
    env: Rc<RefCell<Env>>,
}

impl SymbolNode {
    pub fn new(name: String, env: Rc<RefCell<Env>>) -> Self {
        Self { name, env }
    }

    pub fn name(&self) -> &str {
        &self.name
    }
}

impl AstNode for SymbolNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.env)
    }

    fn apply(&self, env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        env.borrow()
            .resolve(&self.name)
            .ok_or_else(|| AstError::SymbolNotFound(self.name.clone()))
    }

    fn to_json(&self) -> Value {
        Value::String(self.name.clone())
    }

    fn is_symbol_named(&self, name: &str) -> bool {
        self.name == name
    }
}

/// Array node (function call or regular array)
pub struct ArrayNode {
    elements: Vec<Box<dyn AstNode>>,
    env: Rc<RefCell<Env>>,
}

impl ArrayNode {
    pub fn new(elements: Vec<Box<dyn AstNode>>, env: Rc<RefCell<Env>>) -> Self {
        Self { elements, env }
    }

    fn is_empty(&self) -> bool {
        self.elements.is_empty()
    }

    fn first(&self) -> Option<&dyn AstNode> {
        self.elements.first().map(|b| b.as_ref())
    }

    fn rest(&self) -> &[Box<dyn AstNode>] {
        if self.elements.is_empty() {
            &[]
        } else {
            &self.elements[1..]
        }
    }
}

impl AstNode for ArrayNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.env)
    }

    fn apply(&self, env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        if self.is_empty() {
            return Ok(Value::Array(vec![]));
        }

        // Check if first element is a symbol (function call)
        // Try each special form name
        const SPECIAL_FORMS: &[&str] = &["$def", "$defn", "$lambda", "$quote"];

        if let Some(first) = self.first() {
            for &symbol in SPECIAL_FORMS {
                if first.is_symbol_named(symbol) {
                    return self.apply_function_call(env, symbol);
                }
            }

            // Check if it's any symbol
            if let Value::String(name) = first.to_json() {
                if name.starts_with('$') && name != "$*" && !name.starts_with("$$") {
                    return self.apply_function_call(env, &name);
                }
            }
        }

        // Regular array - evaluate all elements
        let evaluated: Result<Vec<_>, _> = self.elements
            .iter()
            .map(|node| node.apply(env))
            .collect();
        Ok(Value::Array(evaluated?))
    }

    fn to_json(&self) -> Value {
        let arr: Vec<_> = self.elements.iter().map(|n| n.to_json()).collect();
        Value::Array(arr)
    }
}

impl ArrayNode {
    fn apply_function_call(&self, env: &Rc<RefCell<Env>>, symbol: &str) -> Result<Value, AstError> {
        // Special forms that don't evaluate arguments
        const SPECIAL_FORMS: &[&str] = &["$def", "$defn", "$lambda", "$quote"];

        if SPECIAL_FORMS.contains(&symbol) {
            // Pass unevaluated arguments
            let args: Vec<&dyn AstNode> = self.rest().iter().map(|b| b.as_ref()).collect();
            return env.borrow().apply_functor_node(symbol, &args);
        }

        // Regular functors - evaluate arguments first
        let evaluated_args: Result<Vec<_>, _> = self.rest()
            .iter()
            .map(|node| node.apply(env))
            .collect();

        env.borrow().apply_functor_values(symbol, &evaluated_args?)
    }
}

/// Object node with key-value pairs
pub struct ObjectNode {
    dict: HashMap<String, Box<dyn AstNode>>,
    env: Rc<RefCell<Env>>,
}

impl ObjectNode {
    pub fn new(dict: HashMap<String, Box<dyn AstNode>>, env: Rc<RefCell<Env>>) -> Self {
        Self { dict, env }
    }
}

impl AstNode for ObjectNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.env)
    }

    fn apply(&self, env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        let mut result = Map::new();
        for (key, node) in &self.dict {
            let value = node.apply(env)?;
            result.insert(key.clone(), value);
        }
        Ok(Value::Object(result))
    }

    fn to_json(&self) -> Value {
        let mut map = Map::new();
        for (key, node) in &self.dict {
            map.insert(key.clone(), node.to_json());
        }
        Value::Object(map)
    }
}

/// Object expression node ({"$operator": value, "meta": ...})
pub struct ObjectExpressionNode {
    operator: String,
    value: Box<dyn AstNode>,
    /// Metadata associated with this expression
    metadata: HashMap<String, Value>,
    env: Rc<RefCell<Env>>,
}

impl ObjectExpressionNode {
    pub fn new(
        operator: String,
        value: Box<dyn AstNode>,
        metadata: HashMap<String, Value>,
        env: Rc<RefCell<Env>>
    ) -> Self {
        Self { operator, value, metadata, env }
    }
}

impl AstNode for ObjectExpressionNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.env)
    }

    fn apply(&self, env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        // Special handling for $expr - return value as-is
        if self.operator == "$expr" {
            return self.value.apply(env);
        }

        // Set metadata context before calling functor
        // Use a separate scope to ensure borrow is dropped
        {
            let mut env_mut = env.borrow_mut();
            env_mut.set_meta(self.metadata.clone());
        }

        let result = if self.operator == "$pattern" || self.operator == "$query" || self.operator == "$sql" {
            // Special handling for $pattern and $query
            // Pass unevaluated JSON for these operators
            let json_value = self.value.to_json();
            env.borrow().apply_functor_values(&self.operator, &[json_value])
        } else {
            // For other operators, evaluate and apply as functor
            let evaluated = self.value.apply(env)?;
            env.borrow().apply_functor_values(&self.operator, &[evaluated])
        };

        // Clear metadata context after functor call
        {
            let mut env_mut = env.borrow_mut();
            env_mut.clear_meta();
        }

        result
    }

    fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert(self.operator.clone(), self.value.to_json());
        // Include metadata in JSON representation
        for (key, value) in &self.metadata {
            map.insert(key.clone(), value.clone());
        }
        Value::Object(map)
    }
}

/// Quote node (returns unevaluated expression)
pub struct QuoteNode {
    value: Box<dyn AstNode>,
    env: Rc<RefCell<Env>>,
}

impl QuoteNode {
    pub fn new(value: Box<dyn AstNode>, env: Rc<RefCell<Env>>) -> Self {
        Self { value, env }
    }
}

impl AstNode for QuoteNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.env)
    }

    fn apply(&self, _env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        // Return the AST node itself as JSON
        Ok(self.value.to_json())
    }

    fn to_json(&self) -> Value {
        self.value.to_json()
    }
}

/// Lambda node (closure with static scoping)
pub struct LambdaNode {
    params: Vec<String>,
    body: Box<dyn AstNode>,
    closure_env: Rc<RefCell<Env>>,
}

impl LambdaNode {
    pub fn new(params: Vec<String>, body: Box<dyn AstNode>, closure_env: Rc<RefCell<Env>>) -> Self {
        Self { params, body, closure_env }
    }
}

impl AstNode for LambdaNode {
    fn get_env(&self) -> Rc<RefCell<Env>> {
        Rc::clone(&self.closure_env)
    }

    fn apply(&self, env: &Rc<RefCell<Env>>) -> Result<Value, AstError> {
        // Lambda evaluation returns a lambda object (for now)
        // In a full implementation, this would be callable
        let mut lambda_obj = serde_json::Map::new();
        lambda_obj.insert("__lambda__".to_string(), Value::Bool(true));
        lambda_obj.insert("params".to_string(), Value::Array(
            self.params.iter().cloned().map(Value::String).collect()
        ));
        // Store body as JSON
        lambda_obj.insert("body".to_string(), self.body.to_json());
        Ok(Value::Object(lambda_obj))
    }

    fn to_json(&self) -> Value {
        // Lambda nodes can't be directly serialized to JSON
        // Return a placeholder
        Value::String("<lambda>".to_string())
    }
}
