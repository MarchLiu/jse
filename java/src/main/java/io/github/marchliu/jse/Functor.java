package io.github.marchliu.jse;

/**
 * Functional interface for JSE functors (operators).
 *
 * <p>A functor takes an environment and variable arguments,
 * and returns a result value.</p>
 *
 * @param env Execution environment
 * @param args Evaluated arguments
 * @return Result value
 */
@FunctionalInterface
public interface Functor {

    /**
     * Apply this functor with the given environment and arguments.
     *
     * @param env Execution environment
     * @param args Arguments (already evaluated)
     * @return Result value
     */
    Object apply(Env env, Object... args);
}
