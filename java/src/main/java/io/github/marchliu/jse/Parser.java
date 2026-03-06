package io.github.marchliu.jse;

import io.github.marchliu.jse.ast.*;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Parser for converting JSON values to AST nodes.
 *
 * <p>Follows the formal semantics:
 * <ul>
 *   <li>Symbols: strings starting with {@code $} but not {@code $$} (except {@code $*} wildcard)</li>
 *   <li>Arrays: parsed as ArrayNode, with special handling for {@code $quote}</li>
 *   <li>Objects: parsed as ObjectNode or ObjectExpressionNode</li>
 * </ul>
 * </p>
 */
public class Parser {

    private final Env env;

    /**
     * Create a parser with the given environment.
     *
     * @param env Environment to pass to constructed AST nodes
     */
    public Parser(Env env) {
        this.env = env;
    }

    /**
     * Parse a JSON value into an AST node or return primitive.
     *
     * @param expr JSON value to parse
     * @return AST node or primitive value
     */
    public Object parse(Object expr) {
        // Primitives - wrap in LiteralNode
        if (expr == null || expr instanceof Number || expr instanceof Boolean) {
            return new LiteralNode(expr, env);
        }

        // Strings - check if symbol
        if (expr instanceof String s) {
            if (isSymbol(s)) {
                return new SymbolNode(s, env);
            }
            return new LiteralNode(unescape(s), env);
        }

        // Lists - check for expression form
        if (expr instanceof List<?> list) {
            return parseList(list);
        }

        // Objects - check for expression form
        if (expr instanceof Map<?, ?> map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> obj = (Map<String, Object>) map;
            return parseDict(obj);
        }

        // Unknown type - wrap as literal
        return new LiteralNode(expr, env);
    }

    /**
     * Parse list expression.
     *
     * <p>Forms:
     * <ul>
     *   <li>{@code ["$quote", x]} -> QuoteNode</li>
     *   <li>{@code [symbol, ...]} -> ArrayNode (function call)</li>
     *   <li>{@code [...]} -> ArrayNode (regular array)</li>
     * </ul>
     * </p>
     */
    private Object parseList(List<?> list) {
        if (list.isEmpty()) {
            return new ArrayNode(new ArrayList<>(), env);
        }

        Object first = list.get(0);

        // Special case: $quote
        if ("$quote".equals(first)) {
            Object value = list.size() > 1 ? list.get(1) : null;
            return new QuoteNode(value, env);
        }

        // Check if this is a function call form
        if (first instanceof String s && isSymbol(s)) {
            List<Object> elements = new ArrayList<>(list.size());
            for (Object item : list) {
                elements.add(parse(item));
            }
            return new ArrayNode(elements, env);
        }

        // Regular array - parse all elements
        List<Object> elements = new ArrayList<>(list.size());
        for (Object item : list) {
            elements.add(parse(item));
        }
        return new ArrayNode(elements, env);
    }

    /**
     * Parse dict expression.
     *
     * <p>Forms:
     * <ul>
     *   <li>{@code {"$quote": x}} -> QuoteNode</li>
     *   <li>{@code {symbol: value}} -> ObjectExpressionNode (exactly one symbol key)</li>
     *   <li>{@code {...}} -> ObjectNode with regular keys</li>
     * </ul>
     * </p>
     */
    private Object parseDict(Map<String, Object> dict) {
        // Find symbol keys
        List<String> symbolKeys = new ArrayList<>();
        for (String key : dict.keySet()) {
            if (isSymbol(key)) {
                symbolKeys.add(key);
            }
        }

        if (symbolKeys.isEmpty()) {
            // Regular object - parse all values
            Map<String, Object> result = new LinkedHashMap<>();
            for (Map.Entry<String, Object> entry : dict.entrySet()) {
                String unescapedKey = unescape(entry.getKey());
                result.put(unescapedKey, parse(entry.getValue()));
            }
            return new ObjectNode(result, env);
        }

        if (symbolKeys.size() == 1) {
            // Operator form: {"$operator": value, "meta": ...}
            String operator = symbolKeys.get(0);

            // Special case: $quote
            if ("$quote".equals(operator)) {
                return new QuoteNode(dict.get(operator), env);
            }

            // Parse the value
            Object parsedValue = parse(dict.get(operator));

            // Parse metadata (other keys)
            Map<String, Object> metadata = new LinkedHashMap<>();
            for (Map.Entry<String, Object> entry : dict.entrySet()) {
                if (!entry.getKey().equals(operator)) {
                    String unescapedKey = unescape(entry.getKey());
                    metadata.put(unescapedKey, parse(entry.getValue()));
                }
            }

            return new ObjectExpressionNode(operator, parsedValue, metadata, env);
        }

        // Multiple symbol keys - error per formal semantics
        throw new IllegalArgumentException("JSE structure error: object cannot have multiple operator keys");
    }

    /**
     * Check if string is a JSE symbol.
     *
     * <p>Symbols start with {@code $} but not {@code $$}.
     * Wildcard {@code $*} is NOT a symbol.</p>
     *
     * @param s String to check
     * @return true if string is a symbol
     */
    public static boolean isSymbol(String s) {
        // Wildcard $* is a literal string, not a symbol
        if ("$*".equals(s)) {
            return false;
        }
        return s.startsWith("$") && !s.startsWith("$$");
    }

    /**
     * Unescape {@code $$}-prefixed string.
     *
     * @param s String to unescape
     * @return Unescaped string
     */
    private static String unescape(String s) {
        if (s.startsWith("$$")) {
            return s.substring(1);
        }
        return s;
    }
}
