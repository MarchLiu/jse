package io.github.marchliu.jse;

import io.github.marchliu.jse.functors.UtilsFunctors;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class LogicTest {

    private Engine createEngine() {
        Env env = new Env();
        env.load(UtilsFunctors.UTILS_FUNCTORS);
        return new Engine(env);
    }

    @Test
    void andBasic() {
        Engine engine = createEngine();
        assertEquals(true, engine.execute(List.of("$and", true, true, true)));
        assertEquals(false, engine.execute(List.of("$and", true, false, true)));
    }

    @Test
    void orBasic() {
        Engine engine = createEngine();
        assertEquals(true, engine.execute(List.of("$or", false, false, true)));
        assertEquals(false, engine.execute(List.of("$or", false, false, false)));
    }

    @Test
    void notBasic() {
        Engine engine = createEngine();
        assertEquals(false, engine.execute(List.of("$not", true)));
        assertEquals(true, engine.execute(List.of("$not", false)));
    }

    @Test
    void nestedLogic() {
        Engine engine = createEngine();
        List<Object> expr = List.of(
                "$or",
                List.of("$and", true, List.of("$not", false)),
                List.of("$and", false, true)
        );
        assertEquals(true, engine.execute(expr));
    }

    @Test
    void deepNesting() {
        Engine engine = createEngine();
        List<Object> expr = List.of(
                "$not",
                List.of(
                        "$or",
                        List.of("$and", false, List.of("$not", false)),
                        List.of("$not", true)
                )
        );
        assertEquals(true, engine.execute(expr));
    }
}
