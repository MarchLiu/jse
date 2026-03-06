package ast

import (
	"fmt"
	"strings"

	"github.com/MarchLiu/jse/gojse/functors"
)

// LiteralNode represents a literal value (numbers, strings, bool, null).
type LiteralNode struct {
	value interface{}
	env   interface{}
}

func NewLiteralNode(value interface{}, env interface{}) *LiteralNode {
	return &LiteralNode{value: value, env: env}
}

func (n *LiteralNode) Apply(env interface{}) (interface{}, error) {
	return n.value, nil
}

func (n *LiteralNode) ToJSON() interface{} {
	return n.value
}

func (n *LiteralNode) GetEnv() interface{} {
	return n.env
}

// SymbolNode represents a variable reference.
type SymbolNode struct {
	name string
	env  interface{}
}

func NewSymbolNode(name string, env interface{}) *SymbolNode {
	return &SymbolNode{name: name, env: env}
}

func (n *SymbolNode) Apply(env interface{}) (interface{}, error) {
	// TODO: Implement symbol resolution through Env interface
	return nil, fmt.Errorf("symbol resolution not yet implemented: %s", n.name)
}

func (n *SymbolNode) ToJSON() interface{} {
	return n.name
}

func (n *SymbolNode) GetEnv() interface{} {
	return n.env
}

func (n *SymbolNode) Name() string {
	return n.name
}

// ArrayNode represents a function call or regular array.
type ArrayNode struct {
	elements []AstNode
	env      interface{}
}

func NewArrayNode(elements []AstNode, env interface{}) *ArrayNode {
	return &ArrayNode{elements: elements, env: env}
}

func (n *ArrayNode) Apply(env interface{}) (interface{}, error) {
	if len(n.elements) == 0 {
		return []interface{}{}, nil
	}

	// Check if first element is a symbol (function call)
	first := n.elements[0]
	if sym, ok := first.(*SymbolNode); ok && isSymbol(sym.Name()) {
		return n.applyFunctionCall(env, sym.Name())
	}

	// Regular array - evaluate all elements
	result := make([]interface{}, len(n.elements))
	for i, el := range n.elements {
		v, err := el.Apply(env)
		if err != nil {
			return nil, err
		}
		result[i] = v
	}
	return result, nil
}

func (n *ArrayNode) ToJSON() interface{} {
	result := make([]interface{}, len(n.elements))
	for i, el := range n.elements {
		result[i] = el.ToJSON()
	}
	return result
}

func (n *ArrayNode) GetEnv() interface{} {
	return n.env
}

func (n *ArrayNode) applyFunctionCall(env interface{}, symbol string) (interface{}, error) {
	// Special forms that don't evaluate arguments
	specialForms := map[string]bool{
		"$quote": true,
	}

	// Get rest of arguments (elements after the first)
	rest := n.rest()

	if specialForms[symbol] {
		// Pass unevaluated arguments
		args := make([]interface{}, len(rest))
		for i, el := range rest {
			args[i] = el.ToJSON()
		}
		return n.applyFunctor(env, symbol, args)
	}

	// Regular functors - evaluate arguments first
	evaluated := make([]interface{}, len(rest))
	for i, el := range rest {
		v, err := el.Apply(env)
		if err != nil {
			return nil, err
		}
		evaluated[i] = v
	}
	return n.applyFunctor(env, symbol, evaluated)
}

func (n *ArrayNode) rest() []AstNode {
	if len(n.elements) <= 1 {
		return []AstNode{}
	}
	return n.elements[1:]
}

func (n *ArrayNode) applyFunctor(env interface{}, symbol string, args []interface{}) (interface{}, error) {
	envImpl, ok := env.(functors.Env)
	if !ok {
		return nil, fmt.Errorf("env does not implement functor.Env interface")
	}
	return envImpl.ApplyFunctor(symbol, args)
}

// ObjectNode represents a key-value pair object.
type ObjectNode struct {
	dict map[string]AstNode
	env  interface{}
}

func NewObjectNode(dict map[string]AstNode, env interface{}) *ObjectNode {
	return &ObjectNode{dict: dict, env: env}
}

func (n *ObjectNode) Apply(env interface{}) (interface{}, error) {
	result := make(map[string]interface{})
	for key, node := range n.dict {
		v, err := node.Apply(env)
		if err != nil {
			return nil, err
		}
		result[key] = v
	}
	return result, nil
}

func (n *ObjectNode) ToJSON() interface{} {
	result := make(map[string]interface{})
	for key, node := range n.dict {
		result[key] = node.ToJSON()
	}
	return result
}

func (n *ObjectNode) GetEnv() interface{} {
	return n.env
}

// ObjectExpressionNode represents {"$operator": value}.
type ObjectExpressionNode struct {
	operator string
	value    AstNode
	env      interface{}
}

func NewObjectExpressionNode(operator string, value AstNode, env interface{}) *ObjectExpressionNode {
	return &ObjectExpressionNode{operator: operator, value: value, env: env}
}

func (n *ObjectExpressionNode) Apply(env interface{}) (interface{}, error) {
	// Special handling for $expr
	if n.operator == "$expr" {
		return n.value.Apply(env)
	}

	// Special handling for $pattern and $query - pass unevaluated JSON
	if n.operator == "$pattern" || n.operator == "$query" {
		jsonValue := n.value.ToJSON()
		return n.applyFunctor(env, n.operator, []interface{}{jsonValue})
	}

	// For other operators, evaluate and apply
	evaluated, err := n.value.Apply(env)
	if err != nil {
		return nil, err
	}

	return n.applyFunctor(env, n.operator, []interface{}{evaluated})
}

func (n *ObjectExpressionNode) applyFunctor(env interface{}, symbol string, args []interface{}) (interface{}, error) {
	envImpl, ok := env.(functors.Env)
	if !ok {
		return nil, fmt.Errorf("env does not implement functor.Env interface")
	}
	return envImpl.ApplyFunctor(symbol, args)
}

func (n *ObjectExpressionNode) ToJSON() interface{} {
	return map[string]interface{}{n.operator: n.value.ToJSON()}
}

func (n *ObjectExpressionNode) GetEnv() interface{} {
	return n.env
}

// QuoteNode returns unevaluated expression.
type QuoteNode struct {
	value AstNode
	env   interface{}
}

func NewQuoteNode(value AstNode, env interface{}) *QuoteNode {
	return &QuoteNode{value: value, env: env}
}

func (n *QuoteNode) Apply(env interface{}) (interface{}, error) {
	return n.value.ToJSON(), nil
}

func (n *QuoteNode) ToJSON() interface{} {
	return n.value.ToJSON()
}

func (n *QuoteNode) GetEnv() interface{} {
	return n.env
}

// LambdaNode represents a closure with static scoping.
type LambdaNode struct {
	params     []string
	body       AstNode
	closureEnv interface{}
}

func NewLambdaNode(params []string, body AstNode, closureEnv interface{}) *LambdaNode {
	return &LambdaNode{
		params:     params,
		body:       body,
		closureEnv: closureEnv,
	}
}

func (n *LambdaNode) Apply(env interface{}) (interface{}, error) {
	// Lambda evaluation returns a lambda object
	result := map[string]interface{}{
		"__lambda__": true,
		"params":     n.params,
		"body":       n.body.ToJSON(),
	}
	return result, nil
}

func (n *LambdaNode) ToJSON() interface{} {
	return "<lambda>"
}

func (n *LambdaNode) GetEnv() interface{} {
	return n.closureEnv
}

// Helper functions

func isSymbol(s string) bool {
	return strings.HasPrefix(s, "$") && !strings.HasPrefix(s, "$$")
}

func unescapeSymbol(s string) string {
	if strings.HasPrefix(s, "$$") {
		return s[1:]
	}
	return s
}
