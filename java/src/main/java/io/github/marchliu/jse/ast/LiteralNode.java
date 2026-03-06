package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;

/**
 * AST node for literal values.
 *
 * <p>Wraps primitive values (null, Number, Boolean, non-symbol strings).
 * Returns itself when applied.</p>
 */
public final class LiteralNode extends AstNode {

    private final Object value;

    /**
     * Create a literal node with the given value.
     *
     * @param value The literal value
     * @param env  Construct-time environment (may be null)
     */
    public LiteralNode(Object value, Env env) {
        super(env);
        this.value = value;
    }

    /**
     * Get the literal value.
     *
     * @return The wrapped value
     */
    public Object value() {
        return value;
    }

    @Override
    public Object apply(Env callEnv) {
        return value;
    }

    @Override
    public String toString() {
        return String.valueOf(value);
    }
}
