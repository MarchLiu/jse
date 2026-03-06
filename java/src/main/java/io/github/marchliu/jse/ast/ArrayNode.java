package io.github.marchliu.jse.ast;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.Functor;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * AST node for array expressions.
 *
 * <p>Can represent either:
 * <ul>
 *   <li>A function call: {@code [operator, args...]}</li>
 *   <li>A regular array: {@code [elements...]}</li>
 * </ul>
 * </p>
 */
public final class ArrayNode extends AstNode {

    private final List<Object> elements;

    /**
     * Special forms that don't evaluate their arguments.
     */
    private static final Set<String> SPECIAL_FORMS = new LinkedHashSet<>(
            Arrays.asList("$def", "$defn", "$lambda", "$quote")
    );

    /**
     * Create an array node with the given elements.
     *
     * @param elements List of elements (may contain AST nodes)
     * @param env      Construct-time environment
     */
    public ArrayNode(List<Object> elements, Env env) {
        super(env);
        this.elements = elements;
    }

    /**
     * Get the elements of this array.
     *
     * @return List of elements
     */
    public List<Object> elements() {
        return elements;
    }

    @Override
    public Object apply(Env callEnv) {
        if (elements.isEmpty()) {
            return new ArrayList<>();
        }

        Object first = elements.get(0);

        // Check if this is a function call form [symbol, args...]
        if (first instanceof SymbolNode sn) {
            String operator = sn.name();

            // Look up the functor
            Object resolved = callEnv.resolve(operator);
            if (resolved == null) {
                throw new IllegalArgumentException("Unknown operator: " + operator);
            }

            // Special forms: pass arguments unevaluated
            if (SPECIAL_FORMS.contains(operator)) {
                if (resolved instanceof Functor functor) {
                    List<Object> args = elements.subList(1, elements.size());
                    return functor.apply(callEnv, args.toArray());
                }
                return resolved;
            }

            // Regular functors: evaluate arguments first
            List<Object> evaluatedArgs = new ArrayList<>(elements.size() - 1);
            for (int i = 1; i < elements.size(); i++) {
                evaluatedArgs.add(callEnv.eval(elements.get(i)));
            }

            if (resolved instanceof Functor functor) {
                return functor.apply(callEnv, evaluatedArgs.toArray());
            }
            return resolved;
        }

        // Regular array - evaluate all elements
        List<Object> result = new ArrayList<>(elements.size());
        for (Object elem : elements) {
            result.add(callEnv.eval(elem));
        }
        return result;
    }

    @Override
    public String toString() {
        return elements.toString();
    }
}
