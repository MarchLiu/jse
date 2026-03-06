package io.github.marchliu.jse;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class BasicTest {

    @Test
    void numberExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        Object result = engine.execute(42);
        assertEquals(42, result);
    }

    @Test
    void floatExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        Object result = engine.execute(3.14);
        assertEquals(3.14, (Double) result, 1e-9);
    }

    @Test
    void stringExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        Object result = engine.execute("hello");
        assertEquals("hello", result);
    }

    @Test
    void booleanExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        assertEquals(true, engine.execute(true));
        assertEquals(false, engine.execute(false));
    }

    @Test
    void nullExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        assertNull(engine.execute(null));
    }

    @Test
    void listExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        Object result = engine.execute(List.of(1, 2, 3));
        assertTrue(result instanceof List<?>);
        assertEquals(List.of(1, 2, 3), result);
    }

    @Test
    void mapExpr() {
        Env env = new Env();
        Engine engine = new Engine(env);
        Object result = engine.execute(Map.of("a", 1, "b", "x"));
        assertTrue(result instanceof Map<?, ?>);
        assertEquals(Map.of("a", 1, "b", "x"), result);
    }
}
