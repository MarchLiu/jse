package functors

import (
	"encoding/json"
	"fmt"
	"strings"
)

// SQLFunctors contains SQL-related operators.
var SQLFunctors = map[string]Functor{
	"$pattern": pattern,
	"$query":   query,
	"$expr":    expr,
}

// QueryFields is the SELECT field list used by $pattern / $query.
const QueryFields = "subject, predicate, object, meta"

func pattern(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 3 {
		return "", fmt.Errorf("$pattern requires (subject, predicate, object)")
	}
	subj, ok1 := args[0].(string)
	pred, ok2 := args[1].(string)
	obj, ok3 := args[2].(string)
	if !ok1 || !ok2 || !ok3 {
		return "", fmt.Errorf("$pattern requires string arguments")
	}
	triple := PatternToTriple(subj, pred, obj)
	cond, err := TripleToSQLCondition(triple)
	if err != nil {
		return "", err
	}
	sql := fmt.Sprintf(
		"select \n    subject, predicate, object, meta \nfrom statement as s \nwhere %s \noffset 0\nlimit 100 \n",
		cond,
	)
	return sql, nil
}

func query(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 1 {
		return "", fmt.Errorf("$query expects [op, patterns array] or [patterns array]")
	}

	// Get Env interface
	envImpl, ok := env.(Env)
	if !ok {
		return "", fmt.Errorf("env does not implement EvalJSON")
	}

	// args[0] is the entire array: [op, patterns] or [patterns]
	rawValue := args[0]
	arr, ok := rawValue.([]interface{})
	if !ok {
		return "", fmt.Errorf("$query expects an array argument")
	}

	// Extract patterns array
	// If first element is a logical operator ($and/$or), extract patterns from second element
	// Otherwise, use the entire array as patterns
	var patterns []interface{}
	if len(arr) >= 2 {
		if op, ok := arr[0].(string); ok && (op == "$and" || op == "$or") {
			if p, ok := arr[1].([]interface{}); ok {
				patterns = p
			} else {
				return "", fmt.Errorf("$query %s: second element must be patterns array", op)
			}
		} else {
			// Use entire array as patterns
			patterns = arr
		}
	} else if len(arr) == 1 {
		// Single pattern - wrap in array
		patterns = arr
	} else {
		return "", fmt.Errorf("$query: empty array")
	}

	// Evaluate each pattern to get SQL string
	var conditions []string
	for _, pattern := range patterns {
		// Evaluate the pattern expression
		result, err := envImpl.EvalJSON(pattern)
		if err != nil {
			return "", fmt.Errorf("failed to evaluate pattern: %w", err)
		}

		sql, ok := result.(string)
		if !ok {
			return "", fmt.Errorf("pattern must evaluate to SQL string")
		}

		// Extract WHERE clause from SQL
		if idx := strings.Index(sql, "where "); idx >= 0 {
			whereStart := idx + 6
			if idx := strings.Index(sql[whereStart:], " offset"); idx >= 0 {
				conditions = append(conditions, fmt.Sprintf("(%s)", strings.TrimSpace(sql[whereStart:whereStart+idx])))
			} else {
				conditions = append(conditions, sql)
			}
		} else {
			conditions = append(conditions, sql)
		}
	}
	where := strings.Join(conditions, " and \n    ")
	sql := fmt.Sprintf(
		"select %s \nfrom statement \nwhere \n    %s \noffset 0\nlimit 100 \n",
		QueryFields,
		where,
	)
	return sql, nil
}

func expr(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) == 0 {
		return nil, nil
	}
	return args[0], nil
}

// PatternToTriple converts $pattern arguments into a triple slice.
func PatternToTriple(subject, predicate, object string) []string {
	if subject == "$*" && object == "$*" {
		return []string{predicate}
	}
	return []string{subject, predicate, object}
}

// TripleToSQLCondition builds a jsonb containment predicate.
func TripleToSQLCondition(triple []string) (string, error) {
	doc := map[string][]string{"triple": triple}
	data, err := json.Marshal(doc)
	if err != nil {
		return "", err
	}
	s := string(data)
	escaped := strings.ReplaceAll(s, "'", "''")
	return fmt.Sprintf("meta @> '%s'", escaped), nil
}
