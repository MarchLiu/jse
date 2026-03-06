package io.github.marchliu.jse;

import java.util.Objects;

/**
 * JSE (JSON Structural Expression) execution engine for Java.
 *
 * <p>This version implements the AST-based architecture matching Python/TypeScript.</p>
 */
public final class Engine {

    private final Env env;
    private final Parser parser;

    /**
     * Create an engine with the given environment.
     *
     * @param env Execution environment
     * @throws NullPointerException if env is null
     */
    public Engine(Env env) {
        this.env = Objects.requireNonNull(env, "env");
        this.parser = new Parser(env);
    }

    /**
     * Execute a JSE expression.
     *
     * <p>Parses the expression into an AST and evaluates it.</p>
     *
     * @param expr JSE expression (JSON value)
     * @return Result of evaluation
     */
    public Object execute(Object expr) {
        Object ast = parser.parse(expr);
        return env.eval(ast);
    }

    /**
     * Get the environment.
     *
     * @return The execution environment
     */
    public Env env() {
        return env;
    }
}
