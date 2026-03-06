package ast

import (
	"fmt"
	"strings"
)

// Parser converts JSON values into AST nodes.
type Parser struct {
	env interface{}
}

// NewParser creates a new Parser with the given environment.
func NewParser(env interface{}) *Parser {
	return &Parser{env: env}
}

// Parse converts a JSON value into an AST node.
func (p *Parser) Parse(value interface{}) (AstNode, error) {
	switch v := value.(type) {
	case nil, bool, float64, float32, int, int32, int64, uint, uint32, uint64:
		return NewLiteralNode(v, p.env), nil

	case string:
		// Strings starting with $ are symbols, but with exceptions
		// $* is a literal wildcard (not a symbol)
		// $$ escapes the $ (so $$* is literal $*)
		if strings.HasPrefix(v, "$") && !strings.HasPrefix(v, "$$") && v != "$*" {
			return NewSymbolNode(v, p.env), nil
		}
		return NewLiteralNode(v, p.env), nil

	case []interface{}:
		return p.parseArray(v)

	case map[string]interface{}:
		return p.parseObject(v)

	default:
		return nil, fmt.Errorf("unsupported type: %T", v)
	}
}

func (p *Parser) parseArray(arr []interface{}) (AstNode, error) {
	elements := make([]AstNode, len(arr))
	for i, el := range arr {
		node, err := p.Parse(el)
		if err != nil {
			return nil, err
		}
		elements[i] = node
	}
	return NewArrayNode(elements, p.env), nil
}

func (p *Parser) parseObject(obj map[string]interface{}) (AstNode, error) {
	// Check for object expression (single key starting with $)
	if sym, ok := getSExprKey(obj); ok {
		value, exists := obj[sym]
		if !exists {
			value = nil
		}
		valueNode, err := p.Parse(value)
		if err != nil {
			return nil, err
		}
		return NewObjectExpressionNode(sym, valueNode, p.env), nil
	}

	// Regular object
	dict := make(map[string]AstNode)
	for key, value := range obj {
		key = unescapeSymbol(key)
		node, err := p.Parse(value)
		if err != nil {
			return nil, err
		}
		dict[key] = node
	}
	return NewObjectNode(dict, p.env), nil
}

// Helper functions

func getSExprKey(obj map[string]interface{}) (string, bool) {
	var found string
	for k := range obj {
		if strings.HasPrefix(k, "$") && !strings.HasPrefix(k, "$$") {
			if found != "" {
				return "", false
			}
			found = k
		}
	}
	if found == "" {
		return "", false
	}
	return found, true
}
