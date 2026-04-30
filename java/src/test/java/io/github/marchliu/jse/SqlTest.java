package io.github.marchliu.jse;

import static org.junit.jupiter.api.Assertions.assertTrue;
import java.util.*;
import io.github.marchliu.jse.functors.SqlFunctors;
import org.junit.jupiter.api.Test;

public class SqlTest {

    private Engine createEngine() {
        Env env = new Env();
        env.load(SqlFunctors.SQL_FUNCTORS);
        return new Engine(env);
    }

    @SuppressWarnings("unchecked")
    private String execute(Map<String, Object> expr) {
        return (String) createEngine().execute(expr);
    }

    @SafeVarargs
    private static <T> List<T> L(T... items) {
        return new ArrayList<>(Arrays.asList(items));
    }

    @Test
    void basicSelectFrom() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$name", "$age"),
            L("$from", "$users")
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("select name, age"));
        assertTrue(sql.contains("from users"));
    }

    @Test
    void nestedAndOr() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$name", "$age"),
            L("$from", "$users"),
            L("$where", L("$and",
                L("$gt", "$age", 18),
                L("$or",
                    L("$eq", "$status", "active"),
                    L("$eq", "$role", "admin"))))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("age > 18"));
        assertTrue(sql.contains("status = 'active'"));
        assertTrue(sql.contains("role = 'admin'"));
    }

    @Test
    void joinWithAlias() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$u.name", "$o.total"),
            L("$from", L("$as", "$users", "$u")),
            L("$join", L("$as", "$orders", "$o"), L("$eq", "$u.id", "$o.user_id")),
            L("$where", L("$gt", "$o.total", 100))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("users as u"));
        assertTrue(sql.contains("join orders as o"));
        assertTrue(sql.contains("u.id = o.user_id"));
    }

    @Test
    void leftJoinNull() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$u.name", "$o.total"),
            L("$from", L("$as", "$users", "$u")),
            L("$left-join", L("$as", "$orders", "$o"), L("$eq", "$u.id", "$o.user_id")),
            L("$where", L("$is", "$o.total", null))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("left join"));
        assertTrue(sql.contains("o.total is null"));
    }

    @Test
    void insert() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$insert-into", "$users", "$name", "$age", "$email"),
            L("$values", "Alice", 30, "alice@example.com")
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("insert into users"));
        assertTrue(sql.contains("'Alice'"));
    }

    @Test
    void delete() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$delete-from", "$sessions"),
            L("$where", L("$lt", "$expired_at", "2024-01-01"))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("delete from sessions"));
        assertTrue(sql.contains("expired_at < '2024-01-01'"));
    }

    @Test
    void update() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$update", "$users"),
            L("$set", Map.of("$age", 31, "$status", "active")),
            L("$where", L("$eq", "$id", 42))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("update users"));
        assertTrue(sql.contains("age = 31"));
        assertTrue(sql.contains("id = 42"));
    }

    @Test
    void dollarEscape() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$name", "$sku"),
            L("$from", "$products"),
            L("$where", L("$and",
                L("$like", "$sku", "$$PROMO-%"),
                L("$is-not", "$deleted_at", null),
                L("$eq", "$is_active", true)))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("sku like '$PROMO-%'"));
        assertTrue(sql.contains("deleted_at is not null"));
        assertTrue(sql.contains("is_active = true"));
    }

    @Test
    void groupByAggregates() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$category",
                L("$as", L("$count", "$*"), "$cnt"),
                L("$as", L("$avg", "$price"), "$avg_price")),
            L("$from", "$products"),
            L("$group-by", "$category"),
            L("$order-by", "$avg_price", "$desc"),
            L("$limit", 50)
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("group by category"));
        assertTrue(sql.contains("count(*)"));
        assertTrue(sql.contains("order by avg_price desc"));
        assertTrue(sql.contains("limit 50"));
    }

    @Test
    void crossJoin() {
        Map<String, Object> expr = Map.of("$sql", L(
            L("$select", "$u.name", "$d.dept_name"),
            L("$from", L("$as", "$users", "$u")),
            L("$cross-join", L("$as", "$departments", "$d"))
        ));
        String sql = execute(expr);
        assertTrue(sql.contains("cross join departments as d"));
    }
}
