package functors

import (
	"fmt"
)

// LispFunctors contains Lisp-style operators.
var LispFunctors = map[string]Functor{
	"$def":   def,
	"$defn":  defn,
	"$lambda": lambda,
}

func def(env interface{}, args []interface{}) (interface{}, error) {
	// TODO: Implement $def
	return nil, fmt.Errorf("$def not yet implemented")
}

func defn(env interface{}, args []interface{}) (interface{}, error) {
	// TODO: Implement $defn
	return nil, fmt.Errorf("$defn not yet implemented")
}

func lambda(env interface{}, args []interface{}) (interface{}, error) {
	// TODO: Implement $lambda
	return nil, fmt.Errorf("$lambda not yet implemented")
}
