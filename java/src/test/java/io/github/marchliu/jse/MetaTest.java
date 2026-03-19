package io.github.marchliu.jse;

import io.github.marchliu.jse.ast.AstNode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for meta mechanism in JSE.
 *
 * <p>Meta mechanism allows passing additional metadata to functors through the
 * environment. When an expression like {"$operator": value, "meta_key": meta_value}
 * is evaluated, the metadata is set in the environment before the functor is called,
 * and cleared after the functor returns.</p>
 */
class MetaTest {

    // Store for side effect testing
    private Map<String, Object> lastMeta;

    // Helper to evaluate meta values (which might be AST nodes)
    private Object evalMetaValue(Env env, Object value) {
        if (value instanceof AstNode node) {
            return env.eval(value);
        }
        return value;
    }

    // A functor that returns the current metadata from the environment
    private final Functor getMeta = (env, args) -> {
        Map<String, Object> meta = env.getMeta();
        Map<String, Object> result = new HashMap<>();
        for (Map.Entry<String, Object> entry : meta.entrySet()) {
            Object evaluated = evalMetaValue(env, entry.getValue());
            result.put(entry.getKey(), evaluated);
        }
        return result;
    };

    // A functor that returns a specific key from metadata
    private final Functor getMetaKey = (env, args) -> {
        if (args.length == 0 || args[0] == null) {
            return null;
        }
        String key = args[0].toString();
        Map<String, Object> meta = env.getMeta();
        if (meta == null || meta.isEmpty()) {
            return null;
        }
        Object value = meta.get(key);
        if (value == null) {
            return null;
        }
        return evalMetaValue(env, value);
    };

    // A functor that returns all metadata plus arguments
    private final Functor metaWithArgs = (env, args) -> {
        Map<String, Object> meta = env.getMeta();
        Map<String, Object> result = new HashMap<>();
        Map<String, Object> metaResult = new HashMap<>();
        for (Map.Entry<String, Object> entry : meta.entrySet()) {
            Object evaluated = evalMetaValue(env, entry.getValue());
            metaResult.put(entry.getKey(), evaluated);
        }
        result.put("meta", metaResult);
        result.put("args", List.of(args));
        return result;
    };

    // A functor that stores meta and returns the argument unchanged
    private final Functor identityWithMeta = (env, args) -> {
        Map<String, Object> meta = env.getMeta();
        lastMeta = new HashMap<>();
        for (Map.Entry<String, Object> entry : meta.entrySet()) {
            Object evaluated = evalMetaValue(env, entry.getValue());
            lastMeta.put(entry.getKey(), evaluated);
        }
        if (args.length > 0) {
            return evalMetaValue(env, args[0]);
        }
        return null;
    };

    private Engine createEngineWithMetaFunctors() {
        Env env = new Env();
        env.register("$get_meta", getMeta);
        env.register("$get_meta_key", getMetaKey);
        env.register("$meta_with_args", metaWithArgs);
        env.register("$identity", identityWithMeta);
        return new Engine(env);
    }

    @BeforeEach
    void setUp() {
        lastMeta = null;
    }

    // --- Basic Meta Passing Tests ---

    @Test
    void testMetaBasicPassing() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta", null);
        expr.put("key1", "value1");
        expr.put("key2", 42);

        Object result = engine.execute(expr);

        assertTrue(result instanceof Map<?, ?>);
        Map<?, ?> resultMap = (Map<?, ?>) result;
        assertTrue(resultMap.containsKey("key1"));
        assertTrue(resultMap.containsKey("key2"));
    }

    @Test
    void testMetaStringValue() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "name");
        expr.put("name", "test_value");

        Object result = engine.execute(expr);
        assertEquals("test_value", result);
    }

    @Test
    void testMetaNumberValue() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "count");
        expr.put("count", 123);

        Object result = engine.execute(expr);
        assertEquals(123, result);
    }

    // --- Multiple Metadata Keys Tests ---

    @Test
    void testMetaMultipleKeys() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new LinkedHashMap<>();
        expr.put("$get_meta", null);
        expr.put("first", "one");
        expr.put("second", "two");
        expr.put("third", 3);

        Object result = engine.execute(expr);

        Map<?, ?> resultMap = (Map<?, ?>) result;
        assertEquals("one", resultMap.get("first"));
        assertEquals("two", resultMap.get("second"));
        assertEquals(3, resultMap.get("third"));
    }

    // --- Meta With Arguments Tests ---

    @Test
    void testMetaWithArgs() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$meta_with_args", List.of("arg1", "arg2"));
        expr.put("meta_key", "meta_value");

        Object result = engine.execute(expr);

        Map<?, ?> resultMap = (Map<?, ?>) result;
        assertTrue(resultMap.containsKey("meta"));
        assertTrue(resultMap.containsKey("args"));

        Map<?, ?> meta = (Map<?, ?>) resultMap.get("meta");
        assertEquals("meta_value", meta.get("meta_key"));
    }

    // --- Meta Lifecycle Tests ---

    @Test
    void testMetaClearedAfterFunctor() {
        Engine engine = createEngineWithMetaFunctors();

        // First call with metadata
        Map<String, Object> expr1 = new HashMap<>();
        expr1.put("$get_meta", null);
        expr1.put("temp_key", "temp_value");

        Object result1 = engine.execute(expr1);
        Map<?, ?> resultMap1 = (Map<?, ?>) result1;
        assertTrue(resultMap1.containsKey("temp_key"));

        // Second call without metadata - should return empty map
        Map<String, Object> expr2 = new HashMap<>();
        expr2.put("$get_meta", null);

        Object result2 = engine.execute(expr2);
        Map<?, ?> resultMap2 = (Map<?, ?>) result2;
        assertTrue(resultMap2.isEmpty());
    }

    @Test
    void testMetaAvailableDuringFunctorExecution() {
        Engine engine = createEngineWithMetaFunctors();
        lastMeta = null;

        Map<String, Object> expr = new HashMap<>();
        expr.put("$identity", "return_value");
        expr.put("stored_key", "stored_value");

        Object result = engine.execute(expr);

        // The result should be the argument
        assertEquals("return_value", result);

        // But the functor should have captured the meta
        assertNotNull(lastMeta);
        assertEquals("stored_value", lastMeta.get("stored_key"));
    }

    // --- Metadata Value Types Tests ---

    @Test
    void testMetaObjectValue() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> config = new LinkedHashMap<>();
        config.put("nested", "value");
        config.put("number", 42);

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "config");
        expr.put("config", config);

        Object result = engine.execute(expr);

        Map<?, ?> resultConfig = (Map<?, ?>) result;
        assertEquals("value", resultConfig.get("nested"));
        assertEquals(42, resultConfig.get("number"));
    }

    @Test
    void testMetaListValue() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "items");
        expr.put("items", List.of(1, 2, 3));

        Object result = engine.execute(expr);

        List<?> items = (List<?>) result;
        assertEquals(3, items.size());
        assertEquals(1, items.get(0));
        assertEquals(2, items.get(1));
        assertEquals(3, items.get(2));
    }

    @Test
    void testMetaNullValue() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "nullable");
        expr.put("nullable", null);

        Object result = engine.execute(expr);
        assertNull(result);
    }

    @Test
    void testMetaBooleanTrue() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "flag");
        expr.put("flag", true);

        Object result = engine.execute(expr);
        assertEquals(true, result);
    }

    @Test
    void testMetaBooleanFalse() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "flag");
        expr.put("flag", false);

        Object result = engine.execute(expr);
        assertEquals(false, result);
    }

    @Test
    void testMetaNestedListValue() {
        Engine engine = createEngineWithMetaFunctors();

        List<List<Integer>> nested = List.of(
            List.of(1, 2),
            List.of(3, 4)
        );

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "nested");
        expr.put("nested", nested);

        Object result = engine.execute(expr);

        List<?> nestedResult = (List<?>) result;
        assertEquals(2, nestedResult.size());
    }

    @Test
    void testMetaComplexObject() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> level1 = new HashMap<>();
        level1.put("level2", "deep_value");

        Map<String, Object> complex = new LinkedHashMap<>();
        complex.put("level1", level1);
        complex.put("array", List.of(1, 2, 3));

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "complex");
        expr.put("complex", complex);

        Object result = engine.execute(expr);

        Map<?, ?> resultComplex = (Map<?, ?>) result;
        Map<?, ?> resultLevel1 = (Map<?, ?>) resultComplex.get("level1");
        assertEquals("deep_value", resultLevel1.get("level2"));

        List<?> arr = (List<?>) resultComplex.get("array");
        assertEquals(3, arr.size());
    }

    // --- Missing Metadata Tests ---

    @Test
    void testMetaMissingKey() {
        Engine engine = createEngineWithMetaFunctors();

        Map<String, Object> expr = new HashMap<>();
        expr.put("$get_meta_key", "nonexistent");

        Object result = engine.execute(expr);
        assertNull(result);
    }
}
