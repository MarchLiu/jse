package jse

import (
	"fmt"

	"github.com/MarchLiu/jse/gojse/ast"
	"github.com/MarchLiu/jse/gojse/functors"
)

// Value is the generic JSON value type used by the engine.
type Value = interface{}

// Functor is a function that takes an environment and arguments.
// Re-exported from functors package for convenience.
type Functor = functors.Functor

// Env represents a JSE execution environment with scope chaining.
type Env struct {
	parent   *Env
	bindings map[string]Value
	functors map[string]functors.Functor
}

// NewEnv creates a new empty environment.
func NewEnv() *Env {
	return &Env{
		parent:   nil,
		bindings: make(map[string]Value),
		functors: make(map[string]functors.Functor),
	}
}

// NewEnvWithParent creates a new environment with a parent (for closures).
func NewEnvWithParent(parent *Env) *Env {
	return &Env{
		parent:   parent,
		bindings: make(map[string]Value),
		functors: make(map[string]functors.Functor),
	}
}

// GetParent returns the parent environment.
func (e *Env) GetParent() *Env {
	return e.parent
}

// Resolve looks up a symbol in the scope chain.
func (e *Env) Resolve(symbol string) (Value, bool) {
	// Check functors first
	if fn, ok := e.functors[symbol]; ok {
		return fn, true
	}
	// Then check bindings
	if v, ok := e.bindings[symbol]; ok {
		return v, true
	}
	// Check parent
	if e.parent != nil {
		return e.parent.Resolve(symbol)
	}
	return nil, false
}

// Register registers a new symbol (throws if exists).
func (e *Env) Register(name string, value Value) error {
	if _, exists := e.bindings[name]; exists {
		return fmt.Errorf("symbol '%s' already exists in current scope", name)
	}
	e.bindings[name] = value
	return nil
}

// Set sets a symbol (overwrites if exists).
func (e *Env) Set(name string, value Value) {
	e.bindings[name] = value
}

// Exists checks if a symbol exists in the scope chain.
func (e *Env) Exists(name string) bool {
	if _, ok := e.bindings[name]; ok {
		return true
	}
	if e.parent != nil {
		return e.parent.Exists(name)
	}
	return false
}

// RegisterFunctor registers a functor.
func (e *Env) RegisterFunctor(name string, functor functors.Functor) {
	e.functors[name] = functor
}

// Load loads a functor module into this environment.
func (e *Env) Load(functors map[string]functors.Functor) {
	for name, fn := range functors {
		e.functors[name] = fn
	}
}

// ResolveFunctor resolves a functor from the environment chain.
func (e *Env) ResolveFunctor(name string) (functors.Functor, bool) {
	if fn, ok := e.functors[name]; ok {
		return fn, true
	}
	if e.parent != nil {
		return e.parent.ResolveFunctor(name)
	}
	return nil, false
}

// ApplyFunctor applies a functor with evaluated values.
func (e *Env) ApplyFunctor(name string, args []interface{}) (interface{}, error) {
	fn, ok := e.ResolveFunctor(name)
	if !ok {
		return nil, fmt.Errorf("unknown symbol: %s", name)
	}
	return fn(e, args)
}

// Eval evaluates an AST node.
func (e *Env) Eval(node ast.AstNode) (Value, error) {
	return node.Apply(e)
}

// EvalJSON parses and evaluates a JSON value.
func (e *Env) EvalJSON(json Value) (Value, error) {
	parser := ast.NewParser(e)
	node, err := parser.Parse(json)
	if err != nil {
		return nil, err
	}
	return node.Apply(e)
}

// --- Backward compatibility ---

// LegacyEnv interface for backward compatibility with v0.1.0.
type LegacyEnv interface {
	Resolve(symbol string) (Value, bool)
}

// legacyEnv wraps the new Env to implement the old interface.
type legacyEnv struct {
	env *Env
}

func (l legacyEnv) Resolve(symbol string) (Value, bool) {
	return l.env.Resolve(symbol)
}

// ExpressionEnv is a minimal environment for backward compatibility.
var ExpressionEnv LegacyEnv = legacyEnv{env: NewEnv()}

// --- Engine ---

// Engine executes JSE expressions.
type Engine struct {
	env    *Env
	parser *ast.Parser
}

// NewEngine constructs a new Engine with the given environment.
func NewEngine(env *Env) *Engine {
	parser := ast.NewParser(env)
	return &Engine{env: env, parser: parser}
}

// WithEnv creates a new Engine with minimal environment (no functors loaded).
// Suitable for basic JSON operations without any functors.
func WithEnv() *Engine {
	env := NewEnv()
	return NewEngine(env)
}

// WithDefaultEnv creates a new Engine with default functors loaded.
// Includes: builtin + utils
// Excludes: lisp (too powerful for most business use), sql (domain-specific)
func WithDefaultEnv() *Engine {
	env := NewEnv()
	env.Load(functors.BuiltinFunctors)
	env.Load(functors.UtilsFunctors)
	return NewEngine(env)
}

// Execute evaluates a JSE expression.
func (e *Engine) Execute(expr Value) (Value, error) {
	// Parse into AST
	node, err := e.parser.Parse(expr)
	if err != nil {
		return nil, err
	}

	// Evaluate using environment
	return e.env.Eval(node)
}

// GetEnv returns the engine's environment.
func (e *Engine) GetEnv() *Env {
	return e.env
}

// --- SQL helpers (for backward compatibility) ---

// QueryFields is the SELECT field list used by $pattern / $query.
const QueryFields = "subject, predicate, object, meta"

// PatternToTriple converts $pattern arguments into a triple slice.
func PatternToTriple(subject, predicate, object string) []string {
	return functors.PatternToTriple(subject, predicate, object)
}

// TripleToSQLCondition builds a jsonb containment predicate.
func TripleToSQLCondition(triple []string) (string, error) {
	return functors.TripleToSQLCondition(triple)
}
