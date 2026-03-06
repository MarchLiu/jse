package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;

/**
 * AST node for symbol references.
 *
 * <p>Represents a symbol like {@code $x}.
 * When applied, looks up the symbol in the call-time environment.</p>
 */
public final class SymbolNode extends AstNode {

    private final String name;

    /**
     * Create a symbol node with the given name.
     *
     * @param name Symbol name (e.g., "$x")
     * @param env  Construct-time environment
     */
    public SymbolNode(String name, Env env) {
        super(env);
        this.name = name;
    }

    /**
     * Get the symbol name.
     *
     * @return The symbol name
     */
    public String name() {
        return name;
    }

    @Override
    public Object apply(Env callEnv) {
        Object value = callEnv.resolve(name);
        if (value == null) {
            throw new IllegalArgumentException("Symbol '" + name + "' not found");
        }
        return value;
    }

    @Override
    public String toString() {
        return name;
    }
}
