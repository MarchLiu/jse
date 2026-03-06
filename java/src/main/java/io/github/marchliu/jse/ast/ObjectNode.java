package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * AST node for plain objects.
 *
 * <p>Represents objects with key-value pairs.
 * Evaluates all values when applied.</p>
 */
public final class ObjectNode extends AstNode {

    private final Map<String, Object> dict;

    /**
     * Create an object node with the given dictionary.
     *
     * @param dict Dictionary of key-value pairs
     * @param env  Construct-time environment
     */
    public ObjectNode(Map<String, Object> dict, Env env) {
        super(env);
        this.dict = dict;
    }

    /**
     * Get the dictionary.
     *
     * @return The dictionary
     */
    public Map<String, Object> dict() {
        return dict;
    }

    @Override
    public Object apply(Env callEnv) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (Map.Entry<String, Object> entry : dict.entrySet()) {
            result.put(entry.getKey(), callEnv.eval(entry.getValue()));
        }
        return result;
    }

    @Override
    public String toString() {
        return dict.toString();
    }
}
