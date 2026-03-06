package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;

/**
 * AST node for quoted (unevaluated) expressions.
 *
 * <p>Represents forms like {@code ["$quote", x]} or {@code {"$quote": x}}.
 * Returns the quoted value without evaluation.</p>
 */
public final class QuoteNode extends AstNode {

    private final Object value;

    /**
     * Create a quote node with the given value.
     *
     * @param value The value to quote (returned unevaluated)
     * @param env  Construct-time environment
     */
    public QuoteNode(Object value, Env env) {
        super(env);
        this.value = value;
    }

    /**
     * Get the quoted value.
     *
     * @return The unevaluated value
     */
    public Object value() {
        return value;
    }

    @Override
    public Object apply(Env callEnv) {
        // Return quoted value without evaluation
        return value;
    }

    @Override
    public String toString() {
        return "(quote " + value + ")";
    }
}
