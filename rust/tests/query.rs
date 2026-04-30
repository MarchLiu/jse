use jse::{Engine, Env, builtin_functors, utils_functors, sql_functors};
use serde_json::json;
use std::rc::Rc;
use std::cell::RefCell;

fn engine() -> Engine {
    let env = Rc::new(RefCell::new(Env::new()));
    env.borrow_mut().load(&builtin_functors());
    env.borrow_mut().load(&utils_functors());
    env.borrow_mut().load(&sql_functors());
    Engine::new(env)
}

#[test]
fn basic_query() {
    let query = json!({
        "$query": ["$quote", ["$pattern", "$*", "author of", "$*"]]
    });
    let result = engine().execute(&query).unwrap();
    let sql = result.as_str().unwrap();
    // Loose checking - look for keywords, not exact format
    assert!(sql.contains("select"));
    assert!(sql.contains("subject, predicate, object, meta"));
    assert!(sql.contains("from statement"));
    assert!(sql.contains("author of"));
    assert!(sql.contains("triple"));
    assert!(sql.contains("offset 0"));
    assert!(sql.contains("limit 100"));
}

#[test]
fn combined_query() {
    let query = json!({
        "$query": {
            "$quote": [
                "$and",
                ["$pattern", "Liu Xin", "author of", "$*"],
                ["$pattern", "$*", "author of", "$*"]
            ]
        }
    });
    let result = engine().execute(&query).unwrap();
    let sql = result.as_str().unwrap();
    assert!(sql.contains("select"));
    assert!(sql.contains("subject, predicate, object, meta"));
    assert!(sql.contains("from statement"));
    assert!(sql.contains("Liu Xin"));
    assert!(sql.contains("author of"));
    assert!(sql.contains(" and "));
    assert!(sql.contains("offset 0"));
    assert!(sql.contains("limit 100"));
}

#[test]
fn sql_select_from() {
    let engine = engine_with_sql();
    let expr = serde_json::json!({"$sql": [["$select","$name","$age"],["$from","$users"]]});
    let result = engine.execute(&expr).unwrap();
    let sql = result.as_str().unwrap();
    assert!(sql.contains("select name, age"));
    assert!(sql.contains("from users"));
}

#[test]
fn sql_nested_and_or() {
    let engine = engine_with_sql();
    let expr = serde_json::json!({"$sql": [
        ["$select","$name","$age"],
        ["$from","$users"],
        ["$where",["$and",
            ["$gt","$age",18],
            ["$or",["$eq","$status","active"],["$eq","$role","admin"]]]]
    ]});
    let sql = engine.execute(&expr).unwrap().as_str().unwrap().to_string();
    assert!(sql.contains("age > 18"));
    assert!(sql.contains("status = 'active'"));
}

#[test]
fn sql_join_alias() {
    let engine = engine_with_sql();
    let expr = serde_json::json!({"$sql": [
        ["$select","$u.name","$o.total"],
        ["$from",["$as","$users","$u"]],
        ["$join",["$as","$orders","$o"],["$eq","$u.id","$o.user_id"]],
        ["$where",["$gt","$o.total",100]]
    ]});
    let sql = engine.execute(&expr).unwrap().as_str().unwrap().to_string();
    assert!(sql.contains("users as u"));
    assert!(sql.contains("join orders as o"));
}

fn engine_with_sql() -> jse::Engine {
    let env = std::rc::Rc::new(std::cell::RefCell::new(jse::Env::new()));
    env.borrow_mut().load(&jse::functors::sql::sql_functors());
    jse::Engine::new(env)
}
