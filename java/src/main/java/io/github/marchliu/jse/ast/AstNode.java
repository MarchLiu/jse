package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.JseValue;

/**
 * Base class for all AST nodes in JSE.
 *
 * <p>Implements the two-env pattern for static scoping:
 * <ul>
 *   <li>Construct-time env ({@link #getEnv()}) - captured when node is created</li>
 *   <li>Call-time env (passed to {@link #apply(Env)}) - used during execution</li>
 * </ul>
 * </p>
 */
public abstract class AstNode implements JseValue {

    /**
     * Construct-time environment.
     * For closures, this is the environment where the lambda was created.
     */
    protected final Env env;

    /**
     * Create an AST node with the given construct-time environment.
     *
     * @param env Construct-time environment (may be null for literals)
     */
    protected AstNode(Env env) {
        this.env = env;
    }

    /**
     * Get the construct-time environment.
     *
     * @return Environment captured at construction time
     */
    public Env getEnv() {
        return env;
    }

    /**
     * Apply this AST node in the given call-time environment.
     *
     * @param callEnv Environment during execution
     * @return Result of evaluation
     */
    public abstract Object apply(Env callEnv);
}
