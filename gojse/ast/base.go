package ast

// AstNode is the interface that all AST nodes must implement.
type AstNode interface {
	// Apply executes this node with the given environment.
	Apply(env interface{}) (interface{}, error)

	// ToJSON converts this node back to its JSON representation.
	ToJSON() interface{}

	// GetEnv returns the construct-time environment (for closures).
	GetEnv() interface{}
}
