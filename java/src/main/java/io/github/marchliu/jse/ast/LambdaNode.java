package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;

import java.util.List;
import java.util.Objects;

/**
 * AST node for lambda functions with closure.
 *
 * <p>Captures the construct-time environment for static scoping.
 * When applied, creates a new environment with the closure as parent.</p>
 */
public final class LambdaNode extends AstNode {

    private final List<String> params;
    private final Object body;
    private final Env closureEnv;

    /**
     * Create a lambda node with the given parameters and body.
     *
     * @param params     Parameter names (e.g., ["$x", "$y"])
     * @param body      Body expression
     * @param closureEnv Environment captured at creation time (for static scoping)
     */
    public LambdaNode(List<String> params, Object body, Env closureEnv) {
        super(closureEnv);
        this.params = params;
        this.body = body;
        this.closureEnv = closureEnv;
    }

    /**
     * Get the parameter names.
     *
     * @return List of parameter names
     */
    public List<String> params() {
        return params;
    }

    /**
     * Get the body expression.
     *
     * @return The body expression
     */
    public Object body() {
        return body;
    }

    /**
     * Get the closure environment.
     *
     * @return Environment captured at creation time
     */
    public Env closureEnv() {
        return closureEnv;
    }

    /**
     * Apply this lambda with the given arguments.
     *
     * <p>Creates a new environment with the closure as parent (static scoping!),
     * binds the parameters to the arguments, and evaluates the body.</p>
     *
     * @param callEnv Call-time environment (used for argument evaluation)
     * @param args    Arguments to bind to parameters
     * @return Result of evaluating the body
     */
    public Object apply(Env callEnv, Object... args) {
        if (args.length != params.size()) {
            throw new IllegalArgumentException(
                    "Lambda expects " + params.size() + " args, got " + args.length
            );
        }

        // Create new environment with closure_env as parent (static scoping!)
        Env newEnv = new Env(closureEnv);

        // Bind parameters to arguments
        for (int i = 0; i < params.size(); i++) {
            newEnv.set(params.get(i), args[i]);
        }

        // Evaluate body in new environment
        return newEnv.eval(body);
    }

    @Override
    public Object apply(Env callEnv) {
        // This should not be called directly - use apply(Env, Object...) instead
        throw new UnsupportedOperationException("Lambda requires arguments. Use apply(Env, Object...) instead.");
    }

    @Override
    public String toString() {
        return "(lambda " + params + " " + body + ")";
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        LambdaNode that = (LambdaNode) o;
        return Objects.equals(params, that.params) && Objects.equals(body, that.body);
    }

    @Override
    public int hashCode() {
        return Objects.hash(params, body);
    }
}
