package io.github.marchliu.jse.functors;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.Functor;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Utility functors for JSE.
 *
 * <p>Includes logical operators ($and, $or, $not) and type predicates.</p>
 */
public final class UtilsFunctors {

    private UtilsFunctors() {}

    /**
     * Logical AND functor.
     */
    public static final Functor AND = (env, args) -> {
        for (Object arg : args) {
            if (!toBoolean(arg)) {
                return false;
            }
        }
        return true;
    };

    /**
     * Logical OR functor.
     */
    public static final Functor OR = (env, args) -> {
        for (Object arg : args) {
            if (toBoolean(arg)) {
                return true;
            }
        }
        return false;
    };

    /**
     * Logical NOT functor.
     */
    public static final Functor NOT = (env, args) -> {
        if (args.length == 0) {
            return true;
        }
        return !toBoolean(args[0]);
    };

    /**
     * Convert value to boolean.
     */
    private static boolean toBoolean(Object value) {
        if (value instanceof Boolean b) {
            return b;
        }
        return value != null;
    }

    /**
     * Dictionary of all utility functors for registration.
     */
    public static final Map<String, Functor> UTILS_FUNCTORS;

    static {
        UTILS_FUNCTORS = new LinkedHashMap<>();
        UTILS_FUNCTORS.put("$and", AND);
        UTILS_FUNCTORS.put("$or", OR);
        UTILS_FUNCTORS.put("$not", NOT);
    }
}
