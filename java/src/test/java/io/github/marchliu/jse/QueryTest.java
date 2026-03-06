package io.github.marchliu.jse;

import io.github.marchliu.jse.functors.SqlFunctors;
import io.github.marchliu.jse.functors.UtilsFunctors;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertTrue;

class QueryTest {

    private Engine createEngine() {
        Env env = new Env();
        env.load(UtilsFunctors.UTILS_FUNCTORS);
        env.load(SqlFunctors.SQL_FUNCTORS);
        return new Engine(env);
    }

    @Test
    void basicQuery() {
        Engine engine = createEngine();
        Map<String, Object> query = Map.of(
                "$expr", List.of("$pattern", "$*", "author of", "$*")
        );

        Object result = engine.execute(query);
        String sql = (String) result;

        assertTrue(sql.contains("select"));
        assertTrue(sql.contains("subject, predicate, object, meta"));
        assertTrue(sql.contains("from statement as s"));
        assertTrue(sql.contains("author of"));
        assertTrue(sql.contains("triple"));
        assertTrue(sql.contains("offset 0"));
        assertTrue(sql.contains("limit 100"));
    }

    @Test
    void combinedQuery() {
        Engine engine = createEngine();
        Map<String, Object> query = Map.of(
                "$query", List.of(
                        "$and",
                        List.of(
                                List.of("$pattern", "Liu Xin", "author of", "$*"),
                                List.of("$pattern", "$*", "author of", "$*")
                        )
                )
        );

        Object result = engine.execute(query);
        String sql = (String) result;

        assertTrue(sql.contains("select " + SqlFunctors.QUERY_FIELDS));
        assertTrue(sql.contains("from statement"));
        assertTrue(sql.contains("Liu Xin"));
        assertTrue(sql.contains("author of"));
        assertTrue(sql.contains(" and "));
        assertTrue(sql.contains("offset 0"));
        assertTrue(sql.contains("limit 100"));
    }
}
