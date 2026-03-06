package functors

import (
	"fmt"
)

// UtilsFunctors contains utility operators.
var UtilsFunctors = map[string]Functor{
	"$not":   not,
	"$list?": listP,
	"$map?":  mapP,
	"$null?": nullP,
	"$get":   get,
	"$set":   set,
	"$del":   del,
	"$conj":  conj,
	"$and":   and,
	"$or":    or,
}

func not(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return true, nil
	}
	return !toBool(args[0]), nil
}

func listP(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return false, nil
	}
	_, ok := args[0].([]interface{})
	return ok, nil
}

func mapP(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return false, nil
	}
	_, ok := args[0].(map[string]interface{})
	return ok, nil
}

func nullP(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return true, nil
	}
	return args[0] == nil, nil
}

func get(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("$get requires at least two arguments")
	}
	obj, ok := args[0].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("$get first argument must be an object")
	}
	key, ok := args[1].(string)
	if !ok {
		return nil, fmt.Errorf("$get second argument must be a string")
	}
	return obj[key], nil
}

func set(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 3 {
		return nil, fmt.Errorf("$set requires at least three arguments")
	}
	obj, ok := args[0].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("$set first argument must be an object")
	}
	key, ok := args[1].(string)
	if !ok {
		return nil, fmt.Errorf("$set second argument must be a string")
	}
	obj[key] = args[2]
	return obj, nil
}

func del(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("$del requires at least two arguments")
	}
	obj, ok := args[0].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("$del first argument must be an object")
	}
	key, ok := args[1].(string)
	if !ok {
		return nil, fmt.Errorf("$del second argument must be a string")
	}
	delete(obj, key)
	return obj, nil
}

func conj(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("$conj requires at least two arguments")
	}
	obj, ok := args[0].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("$conj first argument must be an object")
	}
	key, ok := args[1].(string)
	if !ok {
		return nil, fmt.Errorf("$conj second argument must be a string")
	}
	obj[key] = args[2]
	return obj, nil
}

func and(env interface{}, args []interface{}) (interface{}, error) {
	for _, v := range args {
		if !toBool(v) {
			return false, nil
		}
	}
	return true, nil
}

func or(env interface{}, args []interface{}) (interface{}, error) {
	for _, v := range args {
		if toBool(v) {
			return true, nil
		}
	}
	return false, nil
}

func toBool(v interface{}) bool {
	switch b := v.(type) {
	case bool:
		return b
	case nil:
		return false
	default:
		return true
	}
}
