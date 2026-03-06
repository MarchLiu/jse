package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.Functor;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * AST node for object expressions with an operator key.
 *
 * <p>Represents forms like {@code {"$operator": value, "meta": ...}}.
 * Handles the special case for {@code $expr} which evaluates the whole expression.</p>
 */
public final class ObjectExpressionNode extends AstNode {

    private final String operator;
    private final Object value;
    private final Map<String, Object> metadata;

    /**
     * Create an object expression node.
     *
     * @param operator The operator key (e.g., "$expr")
     * @param value    The value associated with the operator
     * @param metadata Additional metadata keys
     * @param env      Construct-time environment
     */
    public ObjectExpressionNode(String operator, Object value, Map<String, Object> metadata, Env env) {
        super(env);
        this.operator = operator;
        this.value = value;
        this.metadata = metadata;
    }

    /**
     * Get the operator.
     *
     * @return The operator string
     */
    public String operator() {
        return operator;
    }

    /**
     * Get the value.
     *
     * @return The value associated with the operator
     */
    public Object value() {
        return value;
    }

    /**
     * Get the metadata.
     *
     * @return Metadata map
     */
    public Map<String, Object> metadata() {
        return metadata;
    }

    @Override
    public Object apply(Env callEnv) {
        // Look up the functor
        Object resolved = callEnv.resolve(operator);
        if (resolved == null) {
            throw new IllegalArgumentException("Unknown operator: " + operator);
        }

        // For object expressions, we need to evaluate the value as arguments
        // If the value is an ArrayNode, we want to evaluate its elements as data,
        // NOT as a function call (which ArrayNode.apply() would do)
        Object[] args;

        if ("$expr".equals(operator)) {
            // $expr evaluates the whole expression and returns the result
            args = new Object[]{callEnv.eval(value)};
        } else if (value instanceof ArrayNode arrayNode) {
            // Get the elements of the array node and deep evaluate them
            List<Object> elements = arrayNode.elements();
            args = elements.stream()
                    .map(elem -> deepEval(callEnv, elem))
                    .toArray();
        } else {
            // For other types, just evaluate normally
            args = new Object[]{callEnv.eval(value)};
        }

        // Call the functor
        if (resolved instanceof Functor functor) {
            return functor.apply(callEnv, args);
        }
        return resolved;
    }

    /**
     * Deep evaluate a value, handling nested arrays and AST nodes.
     */
    private static Object deepEval(Env env, Object value) {
        // First, evaluate any AST node
        Object evaluated = env.eval(value);

        // If result is an array, recursively evaluate its elements
        if (evaluated instanceof List<?> list) {
            List<Object> result = new ArrayList<>(list.size());
            for (Object item : list) {
                result.add(deepEval(env, item));
            }
            return result;
        }

        // If result is a plain object (not AST node), evaluate its values
        if (evaluated instanceof Map<?, ?> map && !(evaluated instanceof AstNode)) {
            Map<String, Object> result = new LinkedHashMap<>();
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (entry.getKey() instanceof String key) {
                    result.put(key, deepEval(env, entry.getValue()));
                }
            }
            return result;
        }

        return evaluated;
    }

    @Override
    public String toString() {
        return "{" + operator + ": " + value + (metadata.isEmpty() ? "" : ", ...") + "}";
    }
}
