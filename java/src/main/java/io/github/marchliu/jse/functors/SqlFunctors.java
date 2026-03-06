package io.github.marchliu.jse.functors;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.Functor;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * SQL extension functors for JSE.
 *
 * <p>Migrated from the original Sql.java implementation:
 * <ul>
 *   <li>$pattern: Generate SQL for triple pattern matching</li>
 *   <li>$expr: Expression evaluation pass-through</li>
 *   <li>$query: Generate SQL for multi-pattern queries</li>
 * </ul>
 * </p>
 */
public final class SqlFunctors {

    private SqlFunctors() {}

    /** Query field list for SQL SELECT. */
    public static final String QUERY_FIELDS = "subject, predicate, object, meta";

    /** Pattern for extracting WHERE clause from SQL. */
    private static final Pattern WHERE_PATTERN =
            Pattern.compile("where\\s+(.+?)\\s+offset", Pattern.CASE_INSENSITIVE | Pattern.DOTALL);

    /**
     * $pattern functor - Generate SQL for triple pattern matching.
     * Form: [$pattern, subject, predicate, object]
     */
    public static final Functor PATTERN = (env, args) -> {
        if (args.length < 3) {
            throw new IllegalArgumentException("$pattern requires (subject, predicate, object)");
        }

        Object subj = args[0];
        Object pred = args[1];
        Object obj = args[2];

        if (!(subj instanceof String s && pred instanceof String p && obj instanceof String o)) {
            throw new IllegalArgumentException("$pattern requires string arguments");
        }

        List<String> triple = patternToTriple(s, p, o);
        String cond = tripleToSqlCondition(triple);

        return "select \n" +
                "    subject, predicate, object, meta \n" +
                "from statement as s \n" +
                "where " + cond + " \n" +
                "offset 0\n" +
                "limit 100 \n";
    };

    /**
     * $expr functor - Expression evaluation pass-through.
     * Form: [$expr, expression] or {$expr: expression}
     */
    public static final Functor EXPR = (env, args) -> {
        if (args.length == 0) {
            return null;
        }
        return env.eval(args[0]);
    };

    /**
     * $query functor - Generate SQL for multi-pattern query.
     * Form: [$query, op, patterns]
     */
    public static final Functor QUERY = (env, args) -> {
        if (args.length < 2) {
            throw new IllegalArgumentException("$query expects [op, patterns array]");
        }

        // First arg is operator (currently ignored, assumes "and")
        Object op = args[0];
        Object patternsObj = args[1];

        if (!(patternsObj instanceof List<?> patterns)) {
            throw new IllegalArgumentException("$query second argument must be a list");
        }

        List<String> conditions = new ArrayList<>();
        for (Object sqlObj : patterns) {
            if (!(sqlObj instanceof String sql)) {
                throw new IllegalArgumentException("Pattern must evaluate to SQL string");
            }
            Matcher m = WHERE_PATTERN.matcher(sql);
            if (m.find()) {
                conditions.add("(" + m.group(1).trim() + ")");
            } else {
                conditions.add(sql);
            }
        }

        String whereClause = String.join(" and \n    ", conditions);
        return "select " + QUERY_FIELDS + " \n" +
                "from statement \n" +
                "where \n" +
                "    " + whereClause + " \n" +
                "offset 0\n" +
                "limit 100 \n";
    };

    /**
     * Convert $pattern arguments to PostgreSQL jsonb containment triple.
     * <ul>
     *   <li>["*", "author of", "*"] -> ["author of"]</li>
     *   <li>["Liu Xin", "author of", "*"] -> ["Liu Xin", "author of", "*"]</li>
     * </ul>
     */
    public static List<String> patternToTriple(String subject, String predicate, String object) {
        List<String> pattern = new ArrayList<>(3);
        if (!"*".equals(subject)) {
            pattern.add(subject);
        }
        if (!"*".equals(predicate)) {
            pattern.add(predicate);
        }
        if (!"*".equals(object)) {
            pattern.add(object);
        }
        return pattern;
    }

    /**
     * Build SQL WHERE clause for a triple pattern.
     */
    public static String tripleToSqlCondition(List<String> triple) {
        String json = toJson(triple);
        String escaped = json.replace("'", "''");
        return "meta @> '" + escaped + "'";
    }

    /**
     * Convert triple list to JSON string.
     */
    private static String toJson(List<String> triple) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"triple\":[");
        for (int i = 0; i < triple.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append('"').append(escapeJson(triple.get(i))).append('"');
        }
        sb.append("]}");
        return sb.toString();
    }

    /**
     * Escape string for JSON.
     */
    private static String escapeJson(String value) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '\\' -> sb.append("\\\\");
                case '"' -> sb.append("\\\"");
                case '\b' -> sb.append("\\b");
                case '\f' -> sb.append("\\f");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        return sb.toString();
    }

    /**
     * Dictionary of all SQL functors for registration.
     */
    public static final Map<String, Functor> SQL_FUNCTORS;

    static {
        SQL_FUNCTORS = new LinkedHashMap<>();
        SQL_FUNCTORS.put("$pattern", PATTERN);
        SQL_FUNCTORS.put("$expr", EXPR);
        SQL_FUNCTORS.put("$query", QUERY);
    }
}
