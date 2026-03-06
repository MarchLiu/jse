package io.github.marchliu.jse.functors;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.Functor;
import io.github.marchliu.jse.ast.LambdaNode;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * LISP-style functors for JSE.
 *
 * <p>Includes:
 * <ul>
 *   <li>$lambda: Create lambda function with closure</li>
 *   <li>$def: Define symbol in current environment</li>
 *   <li>$defn: Define named function (def + lambda syntax sugar)</li>
 *   <li>$apply: Apply functor to argument list</li>
 *   <li>$eval: Evaluate expression</li>
 * </ul>
 * </p>
 */
public final class LispFunctors {

    private LispFunctors() {}

    /**
     * $lambda functor - Create lambda function with closure.
     * Captures current environment for static scoping.
     */
    public static final Functor LAMBDA = (env, args) -> {
        if (args.length < 2) {
            throw new IllegalArgumentException("$lambda requires (params, body) arguments");
        }

        // Extract parameter names from potentially unevaluated expression
        List<String> paramNames = extractParamNames(args[0]);
        Object body = args.length > 1 ? args[1] : null;

        // Validate all parameter names start with $
        for (String name : paramNames) {
            if (!name.startsWith("$")) {
                throw new IllegalArgumentException("$lambda parameters must be symbols starting with $, got: " + name);
            }
        }

        // Create lambda with current environment as closure (static scoping!)
        return new LambdaNode(paramNames, body, env);
    };

    /**
     * Extract parameter names from potentially unevaluated expression.
     */
    private static List<String> extractParamNames(Object paramsExpr) {
        List<String> names = new ArrayList<>();

        if (paramsExpr instanceof List<?> list) {
            // ArrayNode case
            for (Object p : list) {
                if (p instanceof String) {
                    names.add((String) p);
                } else {
                    throw new IllegalArgumentException("$lambda parameters must be symbols, got: " + p.getClass().getSimpleName());
                }
            }
        } else if (paramsExpr instanceof String) {
            // Single symbol case
            names.add((String) paramsExpr);
        } else {
            throw new IllegalArgumentException("$lambda first argument must be a parameter list");
        }

        return names;
    }

    /**
     * $def functor - Define a symbol in current environment.
     */
    public static final Functor DEF = (env, args) -> {
        if (args.length != 2) {
            throw new IllegalArgumentException("$def requires (name, value) arguments");
        }

        Object nameExpr = args[0];
        Object valueExpr = args[1];

        // Extract name
        String name;
        if (nameExpr instanceof String) {
            name = (String) nameExpr;
            if (!name.startsWith("$")) {
                throw new IllegalArgumentException("First argument must be a symbol starting with $");
            }
        } else {
            throw new IllegalArgumentException("First argument must be a symbol");
        }

        // Evaluate the value expression
        Object value = env.eval(valueExpr);

        env.register(name, value);
        return value;
    };

    /**
     * $defn functor - Define a named function.
     * Syntactic sugar for: [$def, name, [$lambda, params, body]]
     */
    public static final Functor DEFN = (env, args) -> {
        if (args.length < 3) {
            throw new IllegalArgumentException("$defn requires (name, params, body) arguments");
        }

        Object nameExpr = args[0];
        Object paramsExpr = args[1];
        Object body = args.length > 2 ? args[2] : null;

        // Extract name
        String name;
        if (nameExpr instanceof String) {
            name = (String) nameExpr;
            if (!name.startsWith("$")) {
                throw new IllegalArgumentException("First argument must be a symbol starting with $");
            }
        } else {
            throw new IllegalArgumentException("First argument must be a symbol");
        }

        // Create lambda using $lambda functor
        LambdaNode lambdaFn = (LambdaNode) LAMBDA.apply(env, paramsExpr, body);

        // Register it
        env.register(name, lambdaFn);
        return lambdaFn;
    };

    /**
     * $apply functor - Apply functor to argument list.
     */
    public static final Functor APPLY = (env, args) -> {
        if (args.length < 2) {
            throw new IllegalArgumentException("$apply requires (functor, arglist) arguments");
        }

        Object functorObj = env.eval(args[0]);
        Object arglist = env.eval(args[1]);

        if (!(arglist instanceof List<?>)) {
            throw new IllegalArgumentException("$apply second argument must be a list");
        }

        if (!(functorObj instanceof Functor functor)) {
            throw new IllegalArgumentException("$apply first argument must be callable");
        }

        return functor.apply(env, ((List<?>) arglist).toArray());
    };

    /**
     * $eval functor - Evaluate an expression.
     */
    public static final Functor EVAL = (env, args) -> {
        if (args.length == 0) {
            throw new IllegalArgumentException("$eval requires an expression argument");
        }

        return env.eval(args[0]);
    };

    /**
     * Dictionary of all LISP functors for registration.
     */
    public static final Map<String, Functor> LISP_FUNCTORS;

    static {
        LISP_FUNCTORS = new LinkedHashMap<>();
        LISP_FUNCTORS.put("$apply", APPLY);
        LISP_FUNCTORS.put("$eval", EVAL);
        LISP_FUNCTORS.put("$lambda", LAMBDA);
        LISP_FUNCTORS.put("$def", DEF);
        LISP_FUNCTORS.put("$defn", DEFN);
    }
}
