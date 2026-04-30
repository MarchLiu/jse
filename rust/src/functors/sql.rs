//! SQL generation functors for JSE.
//!
//! Implements the $sql functor per Issue #3 v4 design.
//! Also retains legacy $query / $pattern for backward compatibility.

use std::rc::Rc;
use std::cell::RefCell;
use std::collections::HashMap;
use serde_json::Value;
use crate::env::{Env, Functor};
use crate::ast::AstError;
use crate::ast::Parser;

pub const QUERY_FIELDS: &str = "subject, predicate, object, meta";

// ============================================================
// Subquery detection
// ============================================================

fn is_subquery(value: &Value) -> bool {
    match value {
        Value::Array(arr) if !arr.is_empty() => {
            arr.iter().all(|item| {
                matches!(item, Value::Array(clause) if !clause.is_empty()
                    && matches!(&clause[0], Value::String(kw) if kw.starts_with('$')))
            })
        }
        _ => false,
    }
}

// ============================================================
// String utilities
// ============================================================

fn is_symbol_str(s: &str) -> bool {
    if s == "$*" { return false; }
    s.starts_with('$') && !s.starts_with("$$")
}

fn is_escaped_str(s: &str) -> bool {
    s.starts_with("$$")
}

fn sql_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "''"))
}

fn is_parenthesized(s: &str) -> bool {
    if !s.starts_with('(') { return false; }
    let mut depth = 0i32;
    for (i, c) in s.chars().enumerate() {
        match c {
            '(' => depth += 1,
            ')' => depth -= 1,
            _ => {}
        }
        if depth == 0 { return i == s.len() - 1; }
    }
    false
}

// ============================================================
// Expression → SQL fragment renderer
// ============================================================

fn render_expr(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true".to_string() } else { "false".to_string() },
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                if n.as_f64().map(|f| f == i as f64).unwrap_or(false) {
                    return i.to_string();
                }
            }
            n.to_string()
        }
        Value::String(s) => {
            if is_escaped_str(s) { return sql_quote(&format!("${}", &s[2..])); }
            if is_symbol_str(s) { return s[1..].to_string(); }
            sql_quote(s)
        }
        Value::Array(arr) => {
            if arr.is_empty() { return String::new(); }
            if is_subquery(value) { return render_subquery(arr); }
            if let Some(Value::String(first)) = arr.first() {
                if first.starts_with('$') && !first.starts_with("$$") {
                    return render_list_expr(arr);
                }
            }
            arr.iter().map(render_expr).collect::<Vec<_>>().join(", ")
        }
        Value::Object(obj) => render_dict_expr(obj),
    }
}

fn render_dict_expr(d: &serde_json::Map<String, Value>) -> String {
    if d.is_empty() { return String::new(); }
    let op_keys: Vec<&String> = d.keys().filter(|k| is_symbol_str(k)).collect();

    if op_keys.is_empty() || op_keys.len() > 1 {
        return d.iter()
            .map(|(k, v)| format!("{} = {}", render_key(k), render_expr(v)))
            .collect::<Vec<_>>()
            .join(", ");
    }

    let op = op_keys[0];
    if op == "$symbol" {
        return format!("\"{}\"", d[op].as_str().unwrap_or(""));
    }
    render_expr(&d[op])
}

fn render_key(k: &str) -> String {
    if is_symbol_str(k) { return k[1..].to_string(); }
    if is_escaped_str(k) { return format!("${}", &k[2..]); }
    k.to_string()
}

fn render_list_expr(lst: &[Value]) -> String {
    if lst.is_empty() { return String::new(); }
    let op = match &lst[0] {
        Value::String(s) => s,
        _ => return lst.iter().map(render_expr).collect::<Vec<_>>().join(", "),
    };
    if op.starts_with("$$") {
        return lst.iter().map(render_expr).collect::<Vec<_>>().join(", ");
    }
    render_func(op, &lst[1..])
}

// ============================================================
// Function dispatch
// ============================================================

fn render_func(op: &str, args: &[Value]) -> String {
    match op {
        "$as" => render_as(args),
        "$count" => render_count(args),
        "$sum" => render_agg("sum", args),
        "$avg" => render_agg("avg", args),
        "$max" => render_agg("max", args),
        "$min" => render_agg("min", args),
        "$eq" => render_binary("=", args),
        "$ne" => render_binary("!=", args),
        "$gt" => render_binary(">", args),
        "$gte" => render_binary(">=", args),
        "$lt" => render_binary("<", args),
        "$lte" => render_binary("<=", args),
        "$like" => render_binary("like", args),
        "$is" => render_is(args),
        "$is-not" => render_is_not(args),
        "$and" => render_logical("and", args),
        "$or" => render_logical("or", args),
        "$in" => render_in(args),
        "$case" => render_case(args),
        "$excluded" => render_excluded(args),
        _ => {
            let op_name = &op[1..];
            let rendered: Vec<String> = args.iter().map(render_expr).collect();
            format!("{}({})", op_name, rendered.join(", "))
        }
    }
}

fn render_as(args: &[Value]) -> String {
    if args.len() < 2 { return String::new(); }
    let expr = render_expr(&args[0]);
    let alias = render_expr(&args[1]);
    if matches!(args[0], Value::Array(_)) { return format!("({}) as {}", expr, alias); }
    if let Value::String(s) = &args[0] {
        if is_symbol_str(s) { return format!("{} as {}", &s[1..], alias); }
    }
    format!("{} as {}", expr, alias)
}

fn render_count(args: &[Value]) -> String {
    if args.is_empty() { return "count(*)".to_string(); }
    if let Value::String(s) = &args[0] {
        if s == "$*" { return "count(*)".to_string(); }
    }
    format!("count({})", render_expr(&args[0]))
}

fn render_agg(fn_name: &str, args: &[Value]) -> String {
    if args.is_empty() { return format!("{}(*)", fn_name); }
    format!("{}({})", fn_name, render_expr(&args[0]))
}

fn render_binary(op: &str, args: &[Value]) -> String {
    if args.len() < 2 {
        return if args.is_empty() { String::new() } else { render_expr(&args[0]) };
    }
    format!("{} {} {}", render_expr(&args[0]), op, render_expr(&args[1]))
}

fn render_is(args: &[Value]) -> String {
    if args.len() < 2 { return String::new(); }
    let left = render_expr(&args[0]);
    if matches!(&args[1], Value::Null) { return format!("{} is null", left); }
    format!("{} is {}", left, render_expr(&args[1]))
}

fn render_is_not(args: &[Value]) -> String {
    if args.len() < 2 { return String::new(); }
    let left = render_expr(&args[0]);
    if matches!(&args[1], Value::Null) { return format!("{} is not null", left); }
    format!("{} is not {}", left, render_expr(&args[1]))
}

fn render_logical(op: &str, args: &[Value]) -> String {
    if args.is_empty() {
        return if op == "and" { "true".to_string() } else { "false".to_string() };
    }
    let parts: Vec<String> = args.iter().map(|a| {
        let r = render_expr(a);
        if is_parenthesized(&r) { r } else { format!("({})", r) }
    }).collect();
    format!("({})", parts.join(&format!(" {} ", op)))
}

fn render_in(args: &[Value]) -> String {
    if args.len() < 2 { return String::new(); }
    let col = render_expr(&args[0]);
    let val = &args[1];
    if let Value::Array(arr) = val {
        if is_subquery(val) { return format!("{} in ({})", col, render_subquery(arr)); }
        let vals: Vec<String> = arr.iter().map(render_expr).collect();
        return format!("{} in ({})", col, vals.join(", "));
    }
    format!("{} in ({})", col, render_expr(val))
}

fn render_case(args: &[Value]) -> String {
    let mut parts = vec!["case".to_string()];
    let mut else_val: Option<String> = None;
    for arg in args {
        if let Value::Array(arr) = arg {
            if let Some(Value::String(kw)) = arr.first() {
                if kw == "$when" && arr.len() >= 3 {
                    parts.push(format!("when {} then {}", render_expr(&arr[1]), render_expr(&arr[2])));
                } else if kw == "$else" && arr.len() >= 2 {
                    else_val = Some(render_expr(&arr[1]));
                }
            }
        }
    }
    if let Some(ev) = else_val { parts.push(format!("else {}", ev)); }
    parts.push("end".to_string());
    parts.join(" ")
}

fn render_excluded(args: &[Value]) -> String {
    if args.is_empty() { return "excluded".to_string(); }
    format!("excluded.{}", render_expr(&args[0]))
}

// ============================================================
// Subquery rendering
// ============================================================

fn render_subquery(clauses: &[Value]) -> String {
    clauses.iter()
        .filter_map(|c| {
            if let Value::Array(clause) = c {
                let r = render_clause(clause);
                if r.is_empty() { None } else { Some(r) }
            } else { None }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

// ============================================================
// Clause renderer
// ============================================================

fn render_clause(clause: &[Value]) -> String {
    if clause.is_empty() { return String::new(); }
    let kw = match &clause[0] {
        Value::String(s) => s,
        _ => return String::new(),
    };
    if !kw.starts_with('$') { return String::new(); }
    let args = &clause[1..];

    match kw.as_str() {
        "$select" => {
            let cols: Vec<String> = args.iter().map(render_expr).collect();
            format!("select {}", cols.join(", "))
        }
        "$from" => format!("from {}", render_table(args)),
        "$join" => format!("join {}", render_join(args)),
        "$left-join" => format!("left join {}", render_join(args)),
        "$right-join" => format!("right join {}", render_join(args)),
        "$full-join" => format!("full join {}", render_join(args)),
        "$cross-join" => format!("cross join {}", render_table(args)),
        "$where" => {
            if args.is_empty() { String::new() } else { format!("where {}", render_expr(&args[0])) }
        }
        "$group-by" => {
            if args.is_empty() { String::new() } else { format!("group by {}", render_expr(&args[0])) }
        }
        "$having" => {
            if args.is_empty() { String::new() } else { format!("having {}", render_expr(&args[0])) }
        }
        "$order-by" => render_order_by(args),
        "$limit" => {
            if args.is_empty() { String::new() } else { format!("limit {}", render_expr(&args[0])) }
        }
        "$offset" => {
            if args.is_empty() { String::new() } else { format!("offset {}", render_expr(&args[0])) }
        }
        "$with" => render_with(args),
        "$insert-into" => render_insert_into(args),
        "$values" => {
            let vals: Vec<String> = args.iter().map(render_expr).collect();
            format!("values ({})", vals.join(", "))
        }
        "$update" => format!("update {}", render_table(args)),
        "$set" => render_set(args),
        "$delete-from" => format!("delete from {}", render_table(args)),
        "$on-conflict" => {
            if args.is_empty() { String::new() } else { format!("on conflict ({})", render_expr(&args[0])) }
        }
        "$do-update" => render_do_update(args),
        _ => kw[1..].to_string(),
    }
}

fn render_table(args: &[Value]) -> String {
    if args.is_empty() { return String::new(); }
    if let Value::Array(list) = &args[0] {
        if let Some(Value::String(kw)) = list.first() {
            if kw == "$as" { return render_list_expr(list); }
        }
    }
    render_expr(&args[0])
}

fn render_join(args: &[Value]) -> String {
    if args.is_empty() { return String::new(); }
    let table = render_expr(&args[0]);
    if args.len() >= 2 {
        format!("{} on {}", table, render_expr(&args[1]))
    } else { table }
}

fn render_order_by(args: &[Value]) -> String {
    if args.is_empty() { return String::new(); }
    let col = render_expr(&args[0]);
    if args.len() >= 2 {
        if let Value::String(dir) = &args[1] {
            if is_symbol_str(dir) {
                let d = &dir[1..];
                if d == "desc" || d == "asc" { return format!("order by {} {}", col, d); }
            }
        }
        return format!("order by {} {}", col, render_expr(&args[1]));
    }
    format!("order by {}", col)
}

fn render_with(args: &[Value]) -> String {
    if args.is_empty() { return String::new(); }
    let cte_defs = match &args[0] {
        Value::Object(obj) => obj,
        _ => return String::new(),
    };
    let mut cte_parts: Vec<String> = Vec::new();
    for (cte_key, cte_clauses) in cte_defs {
        let cte_name = if is_symbol_str(cte_key) { &cte_key[1..] } else { cte_key.as_str() };
        if let Value::Array(clauses) = cte_clauses {
            if !clauses.is_empty() {
                let inner: Vec<String> = clauses.iter()
                    .filter_map(|c| {
                        if let Value::Array(clause) = c {
                            let r = render_clause(clause);
                            if r.is_empty() { None } else { Some(r) }
                        } else { None }
                    })
                    .collect();
                cte_parts.push(format!("{} as ({})", cte_name, inner.join(" ")));
            }
        }
    }
    if cte_parts.is_empty() { return String::new(); }
    format!("with {}", cte_parts.join(",\n"))
}

fn render_insert_into(args: &[Value]) -> String {
    if args.is_empty() { return "insert into".to_string(); }
    let table = render_expr(&args[0]);
    if args.len() > 1 {
        let cols: Vec<String> = args[1..].iter().map(render_expr).collect();
        format!("insert into {} ({})", table, cols.join(", "))
    } else {
        format!("insert into {}", table)
    }
}

fn render_set(args: &[Value]) -> String {
    if args.is_empty() { return String::new(); }
    let mapping = match &args[0] {
        Value::Object(obj) => obj,
        _ => return String::new(),
    };
    let parts: Vec<String> = mapping.iter()
        .map(|(k, v)| format!("{} = {}", render_key(k), render_expr(v)))
        .collect();
    format!("set {}", parts.join(", "))
}

fn render_do_update(args: &[Value]) -> String {
    if args.is_empty() { return String::new(); }
    let mapping = match &args[0] {
        Value::Object(obj) => obj,
        _ => return String::new(),
    };
    let parts: Vec<String> = mapping.iter()
        .map(|(k, v)| format!("{} = {}", render_key(k), render_expr(v)))
        .collect();
    format!("do update set {}", parts.join(", "))
}

// ============================================================
// $sql functor
// ============================================================

pub fn sql_fn(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    if args.is_empty() { return Ok(Value::String(String::new())); }
    let data = match &args[0] {
        Value::Array(arr) => arr,
        _ => return Ok(Value::String(String::new())),
    };
    if data.is_empty() { return Ok(Value::String(String::new())); }

    let mut parts: Vec<String> = Vec::new();
    let mut pending_values: Vec<Vec<&Value>> = Vec::new();

    let mut flush_values = |parts: &mut Vec<String>, pending: &mut Vec<Vec<&Value>>| {
        if !pending.is_empty() {
            let rows: Vec<String> = pending.iter().map(|vlist| {
                let vals: Vec<String> = vlist.iter().map(|v| render_expr(v)).collect();
                format!("({})", vals.join(", "))
            }).collect();
            parts.push(format!("values {}", rows.join(", ")));
            pending.clear();
        }
    };

    for item in data {
        let clause = match item {
            Value::Array(arr) => arr,
            _ => continue,
        };
        if clause.is_empty() { continue; }
        let kw = match &clause[0] {
            Value::String(s) => s,
            _ => continue,
        };
        if kw == "$values" {
            pending_values.push(clause[1..].iter().collect());
            continue;
        }
        flush_values(&mut parts, &mut pending_values);
        let rendered = render_clause(clause);
        if !rendered.is_empty() { parts.push(rendered); }
    }
    flush_values(&mut parts, &mut pending_values);

    Ok(Value::String(parts.join("\n")))
}

// ============================================================
// Legacy $query / $pattern
// ============================================================

pub fn pattern_to_triple(subject: &str, predicate: &str, object: &str) -> Vec<String> {
    if subject == "$*" && object == "$*" {
        return vec![predicate.to_string()];
    }
    vec![subject.to_string(), predicate.to_string(), object.to_string()]
}

pub fn triple_to_sql_condition(triple: &[String]) -> String {
    let json = serde_json::json!({ "triple": triple });
    let s = json.to_string();
    let escaped = s.replace('\'', "''");
    format!("meta @> '{escaped}'")
}

pub fn pattern(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    if args.len() < 3 {
        return Err(AstError::ArityError("$pattern requires (subject, predicate, object)".to_string()));
    }
    let subj = args[0].as_str()
        .ok_or_else(|| AstError::TypeError("$pattern requires string arguments".to_string()))?;
    let pred = args[1].as_str()
        .ok_or_else(|| AstError::TypeError("$pattern requires string arguments".to_string()))?;
    let obj = args[2].as_str()
        .ok_or_else(|| AstError::TypeError("$pattern requires string arguments".to_string()))?;
    let triple = pattern_to_triple(subj, pred, obj);
    let cond = triple_to_sql_condition(&triple);
    Ok(Value::String(cond))
}

fn and(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    let mut tokens = Vec::new();
    for arg in args {
        let parser = Parser::new(Rc::clone(env));
        let ast = parser.parse(arg)?;
        let result = ast.apply(env)?;
        let sql = result.as_str()
            .ok_or_else(|| AstError::TypeError("$and arguments must evaluate to strings".to_string()))?;
        tokens.push(sql.to_string());
    }
    Ok(Value::String(tokens.join(" and ")))
}

fn wildcard(_env: &Rc<RefCell<Env>>, _args: &[Value]) -> Result<Value, AstError> {
    Ok(Value::String("*".to_string()))
}

fn local_sql_functors() -> HashMap<&'static str, Functor> {
    let mut m = HashMap::new();
    m.insert("$pattern", pattern as Functor);
    m.insert("$and", and as Functor);
    m.insert("$*", wildcard as Functor);
    m
}

pub fn query(env: &Rc<RefCell<Env>>, args: &[Value]) -> Result<Value, AstError> {
    if args.len() < 1 {
        return Err(AstError::ArityError("$query expects a condition expression".to_string()));
    }
    let local = Rc::new(RefCell::new(Env::new_with_parent(Some(Rc::clone(env)))));
    local.borrow_mut().load(&local_sql_functors());
    let parser = Parser::new(Rc::clone(&local));
    let ast = parser.parse(&args[0])?;
    let where_clause = ast.apply(&local)?;
    let where_str = where_clause.as_str()
        .ok_or_else(|| AstError::TypeError("Query condition must evaluate to string".to_string()))?;
    let sql = format!(
        "select {} \nfrom statement \nwhere \n    {} \noffset 0\nlimit 100 \n",
        QUERY_FIELDS, where_str
    );
    Ok(Value::String(sql))
}

pub fn sql_functors() -> HashMap<&'static str, Functor> {
    let mut m = HashMap::new();
    m.insert("$sql", sql_fn as Functor);
    m.insert("$query", query as Functor);
    m
}
