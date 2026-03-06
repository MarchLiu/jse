package io.github.marchliu.jse;

import io.github.marchliu.jse.ast.AstNode;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Environment for JSE execution.
 *
 * <p>Supports parent chaining for scope lookup, symbol registration,
 * and expression evaluation via double-dispatch.</p>
 */
public class Env {

    private final Env parent;
    private final Map<String, Object> bindings;

    /**
     * Create a new environment with no parent.
     */
    public Env() {
        this(null);
    }

    /**
     * Create a new environment with a parent.
     *
     * @param parent Parent environment (for scope chaining)
     */
    public Env(Env parent) {
        this.parent = parent;
        this.bindings = new LinkedHashMap<>();
    }

    /**
     * Get the parent environment.
     *
     * @return Parent environment, or null if this is a top-level environment
     */
    public Env getParent() {
        return parent;
    }

    /**
     * Resolve a symbol in the scope chain.
     *
     * <p>Searches current environment, then parent environments recursively.</p>
     *
     * @param symbol Symbol to resolve (e.g., "$x")
     * @return Resolved value, or null if not found
     */
    public Object resolve(String symbol) {
        if (bindings.containsKey(symbol)) {
            return bindings.get(symbol);
        }
        if (parent != null) {
            return parent.resolve(symbol);
        }
        return null;
    }

    /**
     * Register a new symbol in the current environment.
     *
     * @param name  Symbol name
     * @param value Value to bind
     * @throws IllegalArgumentException if symbol already exists in current scope
     */
    public void register(String name, Object value) {
        if (bindings.containsKey(name)) {
            throw new IllegalArgumentException("Symbol '" + name + "' already exists in current scope");
        }
        bindings.put(name, value);
    }

    /**
     * Set a symbol binding in the current environment.
     *
     * <p>Creates a new binding or overwrites an existing one.</p>
     *
     * @param name  Symbol name
     * @param value Value to bind
     */
    public void set(String name, Object value) {
        bindings.put(name, value);
    }

    /**
     * Check if a symbol exists in the scope chain.
     *
     * @param name Symbol name
     * @return true if symbol exists
     */
    public boolean exists(String name) {
        if (bindings.containsKey(name)) {
            return true;
        }
        if (parent != null) {
            return parent.exists(name);
        }
        return false;
    }

    /**
     * Evaluate an expression.
     *
     * <p>Uses double-dispatch: delegates to {@link AstNode#apply(Env)} for AST nodes,
     * returns primitives as-is.</p>
     *
     * @param expr Expression to evaluate
     * @return Result of evaluation
     */
    public Object eval(Object expr) {
        if (expr instanceof AstNode node) {
            return node.apply(this);
        }
        return expr;  // Primitive value
    }

    /**
     * Load a functor module into the environment.
     *
     * <p>Registers all functors from the module dictionary.</p>
     *
     * @param module Map of functor names to functors
     */
    public void load(Map<String, Functor> module) {
        for (Map.Entry<String, Functor> entry : module.entrySet()) {
            register(entry.getKey(), entry.getValue());
        }
    }
}
