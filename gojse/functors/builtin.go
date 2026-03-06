package functors

import (
	"fmt"
)

// Functor is a function that takes an environment and arguments.
type Functor func(env interface{}, args []interface{}) (interface{}, error)

// Env defines the interface required by functors.
type Env interface {
	ApplyFunctor(name string, args []interface{}) (interface{}, error)
	EvalJSON(json interface{}) (interface{}, error)
}

// BuiltinFunctors contains the basic JSE operators.
var BuiltinFunctors = map[string]Functor{
	"$quote": quote,
	"$eq":    eq,
	"$cond":  cond,
	"$head":  head,
	"$tail":  tail,
	"$atom?": atomP,
	"$cons":  cons,
}

func quote(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return nil, nil
	}
	return args[0], nil
}

func eq(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 2 {
		return false, nil
	}
	first := args[0]
	for _, arg := range args[1:] {
		if !isEqual(first, arg) {
			return false, nil
		}
	}
	return true, nil
}

func cond(env interface{}, args []interface{}) (interface{}, error) {
	for i := 0; i < len(args)-1; i += 2 {
		if i+1 < len(args) {
			condition, ok := args[i].(bool)
			if ok && condition {
				return args[i+1], nil
			}
		}
	}
	if len(args)%2 == 1 {
		return args[len(args)-1], nil
	}
	return nil, nil
}

func head(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("$head requires at least one argument")
	}
	arr, ok := args[0].([]interface{})
	if !ok {
		return nil, fmt.Errorf("$head argument must be an array")
	}
	if len(arr) == 0 {
		return nil, nil
	}
	return arr[0], nil
}

func tail(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("$tail requires at least one argument")
	}
	arr, ok := args[0].([]interface{})
	if !ok {
		return nil, fmt.Errorf("$tail argument must be an array")
	}
	if len(arr) == 0 {
		return []interface{}{}, nil
	}
	return arr[1:], nil
}

func atomP(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return true, nil
	}
	switch args[0].(type) {
	case []interface{}, map[string]interface{}:
		return false, nil
	default:
		return true, nil
	}
}

func cons(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("$cons requires two arguments")
	}
	arr, ok := args[1].([]interface{})
	if !ok {
		return nil, fmt.Errorf("$cons second argument must be an array")
	}
	result := make([]interface{}, 0, len(arr)+1)
	result = append(result, args[0])
	result = append(result, arr...)
	return result, nil
}

// Helper function for equality check
func isEqual(a, b interface{}) bool {
	switch a := a.(type) {
	case bool:
		bb, ok := b.(bool)
		return ok && a == bb
	case float64:
		switch bv := b.(type) {
		case float64:
			return a == bv
		case float32:
			return a == float64(bv)
		case int:
			return a == float64(bv)
		case int32:
			return a == float64(bv)
		case int64:
			return a == float64(bv)
		default:
			return false
		}
	case string:
		bs, ok := b.(string)
		return ok && a == bs
	case nil:
		return b == nil
	case []interface{}:
		bb, ok := b.([]interface{})
		if !ok || len(a) != len(bb) {
			return false
		}
		for i := range a {
			if !isEqual(a[i], bb[i]) {
				return false
			}
		}
		return true
	case map[string]interface{}:
		bb, ok := b.(map[string]interface{})
		if !ok || len(a) != len(bb) {
			return false
		}
		for k := range a {
			if !isEqual(a[k], bb[k]) {
				return false
			}
		}
		return true
	default:
		return false
	}
}
