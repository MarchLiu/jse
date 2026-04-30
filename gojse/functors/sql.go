package functors

import (
	"encoding/json"
	"fmt"
	"strings"
)

// SQLFunctors contains SQL-related operators.
var SQLFunctors = map[string]Functor{
	"$sql":   sqlFn,
	"$query": query,
}

// QueryFields is the SELECT field list used by $query.
const QueryFields = "subject, predicate, object, meta"

// ============================================================
// Subquery detection
// ============================================================

func isSubquery(v interface{}) bool {
	arr, ok := v.([]interface{})
	if !ok || len(arr) == 0 {
		return false
	}
	for _, item := range arr {
		clause, ok := item.([]interface{})
		if !ok || len(clause) == 0 {
			return false
		}
		kw, ok := clause[0].(string)
		if !ok || !strings.HasPrefix(kw, "$") {
			return false
		}
	}
	return true
}

// ============================================================
// String utilities
// ============================================================

func isSymbolStr(s string) bool {
	if s == "$*" {
		return false
	}
	return strings.HasPrefix(s, "$") && !strings.HasPrefix(s, "$$")
}

func isEscapedStr(s string) bool {
	return strings.HasPrefix(s, "$$")
}

func sqlQuote(s string) string {
	escaped := strings.ReplaceAll(s, "'", "''")
	return "'" + escaped + "'"
}

func isParenthesized(s string) bool {
	if !strings.HasPrefix(s, "(") {
		return false
	}
	depth := 0
	for i, c := range s {
		if c == '(' {
			depth++
		} else if c == ')' {
			depth--
		}
		if depth == 0 {
			return i == len(s)-1
		}
	}
	return false
}

// ============================================================
// Expression → SQL fragment renderer
// ============================================================

func renderExpr(v interface{}) string {
	switch val := v.(type) {
	case nil:
		return "null"
	case bool:
		if val {
			return "true"
		}
		return "false"
	case float64:
		// JSON numbers are float64; render integer if possible
		if val == float64(int64(val)) {
			return fmt.Sprintf("%d", int64(val))
		}
		return fmt.Sprintf("%v", val)
	case string:
		if isEscapedStr(val) {
			return sqlQuote("$" + val[2:])
		}
		if isSymbolStr(val) {
			return val[1:]
		}
		return sqlQuote(val)
	case map[string]interface{}:
		return renderDictExpr(val)
	case []interface{}:
		if len(val) == 0 {
			return ""
		}
		if isSubquery(val) {
			return renderSubquery(val)
		}
		first, ok := val[0].(string)
		if ok && strings.HasPrefix(first, "$") && !strings.HasPrefix(first, "$$") {
			return renderListExpr(val)
		}
		// Plain list → comma-separated
		var parts []string
		for _, e := range val {
			parts = append(parts, renderExpr(e))
		}
		return strings.Join(parts, ", ")
	}
	return fmt.Sprintf("%v", v)
}

func renderDictExpr(d map[string]interface{}) string {
	if len(d) == 0 {
		return ""
	}
	// Find $ operator keys
	var opKeys []string
	for k := range d {
		if isSymbolStr(k) {
			opKeys = append(opKeys, k)
		}
	}
	if len(opKeys) == 0 {
		var parts []string
		for k, v := range d {
			parts = append(parts, renderKey(k)+" = "+renderExpr(v))
		}
		return strings.Join(parts, ", ")
	}
	if len(opKeys) > 1 {
		// Multiple $ keys — treat as data mapping
		var parts []string
		for k, v := range d {
			parts = append(parts, renderKey(k)+" = "+renderExpr(v))
		}
		return strings.Join(parts, ", ")
	}
	op := opKeys[0]
	if op == "$symbol" {
		return `"` + fmt.Sprintf("%v", d[op]) + `"`
	}
	return renderExpr(d[op])
}

func renderKey(k interface{}) string {
	s, ok := k.(string)
	if !ok {
		return fmt.Sprintf("%v", k)
	}
	if isSymbolStr(s) {
		return s[1:]
	}
	if isEscapedStr(s) {
		return "$" + s[2:]
	}
	return s
}

func renderListExpr(lst []interface{}) string {
	if len(lst) == 0 {
		return ""
	}
	op, ok := lst[0].(string)
	if !ok {
		var parts []string
		for _, v := range lst {
			parts = append(parts, renderExpr(v))
		}
		return strings.Join(parts, ", ")
	}
	if strings.HasPrefix(op, "$$") {
		var parts []string
		for _, v := range lst {
			parts = append(parts, renderExpr(v))
		}
		return strings.Join(parts, ", ")
	}
	args := lst[1:]
	return renderFunc(op, args)
}

// ============================================================
// Function dispatch
// ============================================================

func renderFunc(op string, args []interface{}) string {
	switch op {
	// Alias
	case "$as":
		return renderAs(args)
	// Aggregates
	case "$count":
		return renderCount(args)
	case "$sum":
		return renderAgg("sum", args)
	case "$avg":
		return renderAgg("avg", args)
	case "$max":
		return renderAgg("max", args)
	case "$min":
		return renderAgg("min", args)
	// Comparisons
	case "$eq":
		return renderBinary("=", args)
	case "$ne":
		return renderBinary("!=", args)
	case "$gt":
		return renderBinary(">", args)
	case "$gte":
		return renderBinary(">=", args)
	case "$lt":
		return renderBinary("<", args)
	case "$lte":
		return renderBinary("<=", args)
	case "$like":
		return renderBinary("like", args)
	case "$is":
		return renderIs(args)
	case "$is-not":
		return renderIsNot(args)
	// Logical
	case "$and":
		return renderLogical("and", args)
	case "$or":
		return renderLogical("or", args)
	// Special
	case "$in":
		return renderIn(args)
	case "$case":
		return renderCase(args)
	case "$excluded":
		return renderExcluded(args)
	}
	// Unknown → generic function call
	opName := op[1:]
	var rendered []string
	for _, a := range args {
		rendered = append(rendered, renderExpr(a))
	}
	return opName + "(" + strings.Join(rendered, ", ") + ")"
}

func renderAs(args []interface{}) string {
	if len(args) < 2 {
		return ""
	}
	expr := renderExpr(args[0])
	alias := renderExpr(args[1])
	if list, ok := args[0].([]interface{}); ok && len(list) > 0 {
		return "(" + expr + ") as " + alias
	}
	if s, ok := args[0].(string); ok && isSymbolStr(s) {
		return s[1:] + " as " + alias
	}
	return expr + " as " + alias
}

func renderCount(args []interface{}) string {
	if len(args) == 0 {
		return "count(*)"
	}
	if s, ok := args[0].(string); ok && s == "$*" {
		return "count(*)"
	}
	return "count(" + renderExpr(args[0]) + ")"
}

func renderAgg(fn string, args []interface{}) string {
	if len(args) == 0 {
		return fn + "(*)"
	}
	return fn + "(" + renderExpr(args[0]) + ")"
}

func renderBinary(op string, args []interface{}) string {
	if len(args) < 2 {
		if len(args) > 0 {
			return renderExpr(args[0])
		}
		return ""
	}
	return renderExpr(args[0]) + " " + op + " " + renderExpr(args[1])
}

func renderIs(args []interface{}) string {
	if len(args) < 2 {
		return ""
	}
	left := renderExpr(args[0])
	if args[1] == nil {
		return left + " is null"
	}
	return left + " is " + renderExpr(args[1])
}

func renderIsNot(args []interface{}) string {
	if len(args) < 2 {
		return ""
	}
	left := renderExpr(args[0])
	if args[1] == nil {
		return left + " is not null"
	}
	return left + " is not " + renderExpr(args[1])
}

func renderLogical(op string, args []interface{}) string {
	if len(args) == 0 {
		if op == "and" {
			return "true"
		}
		return "false"
	}
	var parts []string
	for _, a := range args {
		r := renderExpr(a)
		if isParenthesized(r) {
			parts = append(parts, r)
		} else {
			parts = append(parts, "("+r+")")
		}
	}
	return "(" + strings.Join(parts, " "+op+" ") + ")"
}

func renderIn(args []interface{}) string {
	if len(args) < 2 {
		return ""
	}
	col := renderExpr(args[0])
	val := args[1]
	if arr, ok := val.([]interface{}); ok && isSubquery(arr) {
		inner := renderSubquery(arr)
		return col + " in (" + inner + ")"
	}
	if arr, ok := val.([]interface{}); ok {
		var parts []string
		for _, v := range arr {
			parts = append(parts, renderExpr(v))
		}
		return col + " in (" + strings.Join(parts, ", ") + ")"
	}
	return col + " in (" + renderExpr(val) + ")"
}

func renderCase(args []interface{}) string {
	var parts []string
	parts = append(parts, "case")
	var elseVal string
	hasElse := false
	for _, arg := range args {
		if arr, ok := arg.([]interface{}); ok && len(arr) > 0 {
			if kw, ok := arr[0].(string); ok {
				if kw == "$when" && len(arr) >= 3 {
					parts = append(parts, "when "+renderExpr(arr[1])+" then "+renderExpr(arr[2]))
				} else if kw == "$else" && len(arr) >= 2 {
					elseVal = renderExpr(arr[1])
					hasElse = true
				}
			}
		}
	}
	if hasElse {
		parts = append(parts, "else "+elseVal)
	}
	parts = append(parts, "end")
	return strings.Join(parts, " ")
}

func renderExcluded(args []interface{}) string {
	if len(args) == 0 {
		return "excluded"
	}
	return "excluded." + renderExpr(args[0])
}

// ============================================================
// Subquery rendering
// ============================================================

func renderSubquery(clauses []interface{}) string {
	var parts []string
	for _, c := range clauses {
		if clause, ok := c.([]interface{}); ok {
			rendered := renderClause(clause)
			if rendered != "" {
				parts = append(parts, rendered)
			}
		}
	}
	return strings.Join(parts, " ")
}

// ============================================================
// Clause renderer
// ============================================================

func renderClause(clause []interface{}) string {
	if len(clause) == 0 {
		return ""
	}
	kw, ok := clause[0].(string)
	if !ok || !strings.HasPrefix(kw, "$") {
		return ""
	}
	args := clause[1:]

	switch kw {
	// Query clauses
	case "$select":
		var cols []string
		for _, a := range args {
			cols = append(cols, renderExpr(a))
		}
		return "select " + strings.Join(cols, ", ")

	case "$from":
		return "from " + renderTable(args)

	case "$join":
		return "join " + renderJoin(args)

	case "$left-join":
		return "left join " + renderJoin(args)

	case "$right-join":
		return "right join " + renderJoin(args)

	case "$full-join":
		return "full join " + renderJoin(args)

	case "$cross-join":
		return "cross join " + renderTable(args)

	case "$where":
		if len(args) > 0 {
			return "where " + renderExpr(args[0])
		}
		return ""

	case "$group-by":
		if len(args) > 0 {
			return "group by " + renderExpr(args[0])
		}
		return ""

	case "$having":
		if len(args) > 0 {
			return "having " + renderExpr(args[0])
		}
		return ""

	case "$order-by":
		return renderOrderBy(args)

	case "$limit":
		if len(args) > 0 {
			return "limit " + renderExpr(args[0])
		}
		return ""

	case "$offset":
		if len(args) > 0 {
			return "offset " + renderExpr(args[0])
		}
		return ""

	case "$with":
		return renderWith(args)

	// DML clauses
	case "$insert-into":
		return renderInsertInto(args)

	case "$values":
		var vals []string
		for _, a := range args {
			vals = append(vals, renderExpr(a))
		}
		return "values (" + strings.Join(vals, ", ") + ")"

	case "$update":
		return "update " + renderTable(args)

	case "$set":
		return renderSet(args)

	case "$delete-from":
		return "delete from " + renderTable(args)

	case "$on-conflict":
		if len(args) > 0 {
			return "on conflict (" + renderExpr(args[0]) + ")"
		}
		return ""

	case "$do-update":
		return renderDoUpdate(args)
	}
	return kw[1:]
}

// ============================================================
// Clause helpers
// ============================================================

func renderTable(args []interface{}) string {
	if len(args) == 0 {
		return ""
	}
	first := args[0]
	if arr, ok := first.([]interface{}); ok && len(arr) > 0 {
		if kw, ok := arr[0].(string); ok && kw == "$as" {
			return renderListExpr(arr)
		}
	}
	return renderExpr(first)
}

func renderJoin(args []interface{}) string {
	if len(args) == 0 {
		return ""
	}
	table := renderExpr(args[0])
	if len(args) >= 2 {
		return table + " on " + renderExpr(args[1])
	}
	return table
}

func renderOrderBy(args []interface{}) string {
	if len(args) == 0 {
		return ""
	}
	col := renderExpr(args[0])
	if len(args) >= 2 {
		if dir, ok := args[1].(string); ok && isSymbolStr(dir) {
			d := dir[1:]
			if d == "desc" || d == "asc" {
				return "order by " + col + " " + d
			}
		}
		return "order by " + col + " " + renderExpr(args[1])
	}
	return "order by " + col
}

func renderWith(args []interface{}) string {
	if len(args) == 0 {
		return ""
	}
	cteDefs, ok := args[0].(map[string]interface{})
	if !ok {
		return ""
	}
	var cteParts []string
	for cteNameKey, cteClauses := range cteDefs {
		cteName := cteNameKey
		if isSymbolStr(cteNameKey) {
			cteName = cteNameKey[1:]
		}
		if clauses, ok := cteClauses.([]interface{}); ok && len(clauses) > 0 {
			var innerParts []string
			for _, c := range clauses {
				if clause, ok := c.([]interface{}); ok {
					rendered := renderClause(clause)
					if rendered != "" {
						innerParts = append(innerParts, rendered)
					}
				}
			}
			inner := strings.Join(innerParts, " ")
			cteParts = append(cteParts, cteName+" as ("+inner+")")
		}
	}
	if len(cteParts) == 0 {
		return ""
	}
	return "with " + strings.Join(cteParts, ",\n")
}

func renderInsertInto(args []interface{}) string {
	if len(args) == 0 {
		return "insert into"
	}
	table := renderExpr(args[0])
	if len(args) > 1 {
		var cols []string
		for _, a := range args[1:] {
			cols = append(cols, renderExpr(a))
		}
		return "insert into " + table + " (" + strings.Join(cols, ", ") + ")"
	}
	return "insert into " + table
}

func renderSet(args []interface{}) string {
	if len(args) == 0 {
		return ""
	}
	mapping, ok := args[0].(map[string]interface{})
	if !ok {
		return ""
	}
	var parts []string
	for col, val := range mapping {
		colStr := renderKey(col)
		parts = append(parts, colStr+" = "+renderExpr(val))
	}
	return "set " + strings.Join(parts, ", ")
}

func renderDoUpdate(args []interface{}) string {
	if len(args) == 0 {
		return ""
	}
	mapping, ok := args[0].(map[string]interface{})
	if !ok {
		return ""
	}
	var parts []string
	for col, val := range mapping {
		colStr := renderKey(col)
		parts = append(parts, colStr+" = "+renderExpr(val))
	}
	return "do update set " + strings.Join(parts, ", ")
}

// ============================================================
// Main $sql functor
// ============================================================

func sqlFn(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 1 {
		return "", nil
	}
	data, ok := args[0].([]interface{})
	if !ok {
		return "", fmt.Errorf("$sql expects an array of clauses")
	}
	if len(data) == 0 {
		return "", nil
	}

	// Combine consecutive $values clauses
	var parts []string
	var pendingValues [][]interface{}

	flushValues := func() {
		if len(pendingValues) > 0 {
			var rows []string
			for _, vlist := range pendingValues {
				var vals []string
				for _, v := range vlist {
					vals = append(vals, renderExpr(v))
				}
				rows = append(rows, "("+strings.Join(vals, ", ")+")")
			}
			parts = append(parts, "values "+strings.Join(rows, ", "))
			pendingValues = nil
		}
	}

	for _, item := range data {
		clause, ok := item.([]interface{})
		if !ok || len(clause) == 0 {
			continue
		}
		kw, ok := clause[0].(string)
		if !ok {
			continue
		}
		if kw == "$values" {
			pendingValues = append(pendingValues, clause[1:])
			continue
		}
		flushValues()
		rendered := renderClause(clause)
		if rendered != "" {
			parts = append(parts, rendered)
		}
	}
	flushValues()

	return strings.Join(parts, "\n"), nil
}

// ============================================================
// Legacy $query / $pattern (backward compatibility)
// ============================================================

// envHelper encapsulates environment operations needed by SQL functors.
type envHelper interface {
	EvalJSON(v interface{}) (interface{}, error)
	Load(functors map[string]Functor)
}

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
	return cond, nil
}

func sqlAnd(env interface{}, args []interface{}) (interface{}, error) {
	envImpl, ok := env.(envHelper)
	if !ok {
		return "", fmt.Errorf("env does not implement EvalJSON")
	}
	var tokens []string
	for _, arg := range args {
		result, err := envImpl.EvalJSON(arg)
		if err != nil {
			return "", fmt.Errorf("failed to evaluate $and argument: %w", err)
		}
		sql, ok := result.(string)
		if !ok {
			return "", fmt.Errorf("$and arguments must evaluate to strings")
		}
		tokens = append(tokens, sql)
	}
	return strings.Join(tokens, " and "), nil
}

func wildcard(env interface{}, args []interface{}) (interface{}, error) {
	return "*", nil
}

func localSQLFunctors() map[string]Functor {
	return map[string]Functor{
		"$pattern": pattern,
		"$and":     sqlAnd,
		"$*":       wildcard,
	}
}

func query(env interface{}, args []interface{}) (interface{}, error) {
	if len(args) < 1 {
		return "", fmt.Errorf("$query expects a condition expression")
	}
	envHelper, ok := env.(envHelper)
	if !ok {
		return "", fmt.Errorf("env does not implement required interface")
	}
	localEnv := &localEvalContext{
		parent: envHelper,
		local:  localSQLFunctors(),
	}
	result, err := localEnv.EvalJSON(args[0])
	if err != nil {
		return "", fmt.Errorf("failed to evaluate query condition: %w", err)
	}
	whereStr, ok := result.(string)
	if !ok {
		return "", fmt.Errorf("query condition must evaluate to string, got %T", result)
	}
	sql := fmt.Sprintf(
		"select %s \nfrom statement \nwhere \n    %s \noffset 0\nlimit 100 \n",
		QueryFields,
		whereStr,
	)
	return sql, nil
}

type localEvalContext struct {
	parent envHelper
	local  map[string]Functor
}

func (c *localEvalContext) EvalJSON(v interface{}) (interface{}, error) {
	if m, ok := v.(map[string]interface{}); ok && len(m) == 1 {
		for key, arg := range m {
			if key == "$quote" {
				return c.continueEval(arg)
			}
			if fn, hasLocal := c.local[key]; hasLocal {
				return c.applyFunctor(fn, arg)
			}
		}
	}
	if arr, ok := v.([]interface{}); ok && len(arr) > 0 {
		if key, ok := arr[0].(string); ok {
			if key == "$quote" && len(arr) > 1 {
				return c.continueEval(arr[1])
			}
			if fn, hasLocal := c.local[key]; hasLocal {
				args := arr[1:]
				if len(args) == 1 {
					return c.applyFunctor(fn, args[0])
				}
				return fn(c, args)
			}
		}
	}
	return c.parent.EvalJSON(v)
}

func (c *localEvalContext) continueEval(v interface{}) (interface{}, error) {
	if m, ok := v.(map[string]interface{}); ok && len(m) == 1 {
		for key, arg := range m {
			if fn, hasLocal := c.local[key]; hasLocal {
				result, err := c.applyFunctor(fn, arg)
				if err != nil {
					return nil, err
				}
				return c.continueEval(result)
			}
		}
	}
	if arr, ok := v.([]interface{}); ok && len(arr) > 0 {
		if key, ok := arr[0].(string); ok {
			if fn, hasLocal := c.local[key]; hasLocal {
				args := arr[1:]
				var result interface{}
				var err error
				if len(args) == 1 {
					result, err = c.applyFunctor(fn, args[0])
				} else {
					result, err = fn(c, args)
				}
				if err != nil {
					return nil, err
				}
				return c.continueEval(result)
			}
		}
	}
	return v, nil
}

func (c *localEvalContext) applyFunctor(fn Functor, arg interface{}) (interface{}, error) {
	var args []interface{}
	if arr, ok := arg.([]interface{}); ok {
		args = arr
	} else {
		args = []interface{}{arg}
	}
	return fn(c, args)
}

func (c *localEvalContext) Load(functors map[string]Functor) {
	for name, fn := range functors {
		if _, exists := c.local[name]; !exists {
			c.local[name] = fn
		}
	}
}

func PatternToTriple(subject, predicate, object string) []string {
	if subject == "$*" && object == "$*" {
		return []string{predicate}
	}
	return []string{subject, predicate, object}
}

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
