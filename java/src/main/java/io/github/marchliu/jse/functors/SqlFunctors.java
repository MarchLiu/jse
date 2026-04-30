package io.github.marchliu.jse.functors;

import io.github.marchliu.jse.Env;
import io.github.marchliu.jse.Functor;
import io.github.marchliu.jse.Parser;
import io.github.marchliu.jse.ast.AstNode;
import io.github.marchliu.jse.FunctorBox;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * SQL generation functors for JSE.
 *
 * <p>Implements the $sql functor per Issue #3 v4 design.
 * Also retains legacy $query / $pattern for backward compatibility.</p>
 */
public final class SqlFunctors {

    private SqlFunctors() {}

    public static final String QUERY_FIELDS = "subject, predicate, object, meta";

    // ============================================================
    // Subquery detection
    // ============================================================

    @SuppressWarnings("unchecked")
    private static boolean isSubquery(Object value) {
        if (!(value instanceof List<?> list) || list.isEmpty()) return false;
        for (Object item : list) {
            if (!(item instanceof List<?> clause) || clause.isEmpty()) return false;
            Object first = clause.get(0);
            if (!(first instanceof String kw) || !kw.startsWith("$")) return false;
        }
        return true;
    }

    // ============================================================
    // String utilities
    // ============================================================

    private static boolean isSymbolStr(String s) {
        if ("$*".equals(s)) return false;
        return s.startsWith("$") && !s.startsWith("$$");
    }

    private static boolean isEscapedStr(String s) {
        return s.startsWith("$$");
    }

    private static String sqlQuote(String s) {
        return "'" + s.replace("'", "''") + "'";
    }

    private static boolean isParenthesized(String s) {
        if (!s.startsWith("(")) return false;
        int depth = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '(') depth++;
            else if (c == ')') depth--;
            if (depth == 0) return i == s.length() - 1;
        }
        return false;
    }

    // ============================================================
    // Expression → SQL fragment renderer
    // ============================================================

    @SuppressWarnings("unchecked")
    private static String renderExpr(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean b) return b ? "true" : "false";
        if (value instanceof Number n) {
            if (n.doubleValue() == n.longValue()) return String.valueOf(n.longValue());
            return n.toString();
        }
        if (value instanceof String s) {
            if (isEscapedStr(s)) return sqlQuote("$" + s.substring(2));
            if (isSymbolStr(s)) return s.substring(1);
            return sqlQuote(s);
        }
        if (value instanceof List<?> list) {
            if (list.isEmpty()) return "";
            if (isSubquery(list)) return renderSubquery(list);
            Object first = list.get(0);
            if (first instanceof String s && s.startsWith("$") && !s.startsWith("$$")) {
                return renderListExpr(list);
            }
            return list.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("");
        }
        if (value instanceof Map<?, ?> map) {
            return renderDictExpr((Map<String, Object>) map);
        }
        return String.valueOf(value);
    }

    private static String renderDictExpr(Map<String, Object> d) {
        if (d.isEmpty()) return "";
        List<String> opKeys = new ArrayList<>();
        for (String k : d.keySet()) {
            if (isSymbolStr(k)) opKeys.add(k);
        }
        if (opKeys.isEmpty() || opKeys.size() > 1) {
            List<String> parts = new ArrayList<>();
            for (Map.Entry<String, Object> e : d.entrySet()) {
                parts.add(renderKey(e.getKey()) + " = " + renderExpr(e.getValue()));
            }
            return String.join(", ", parts);
        }
        String op = opKeys.get(0);
        if ("$symbol".equals(op)) return "\"" + d.get(op) + "\"";
        return renderExpr(d.get(op));
    }

    private static String renderKey(Object k) {
        if (k instanceof String s) {
            if (isSymbolStr(s)) return s.substring(1);
            if (isEscapedStr(s)) return "$" + s.substring(2);
            return s;
        }
        return String.valueOf(k);
    }

    private static String renderListExpr(List<?> lst) {
        if (lst.isEmpty()) return "";
        Object op = lst.get(0);
        if (!(op instanceof String s)) {
            return lst.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("");
        }
        if (s.startsWith("$$")) {
            return lst.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("");
        }
        List<Object> args = new ArrayList<>(lst.subList(1, lst.size()));
        return renderFunc(s, args);
    }

    // ============================================================
    // Function dispatch
    // ============================================================

    @SuppressWarnings("unchecked")
    private static String renderFunc(String op, List<Object> args) {
        switch (op) {
            case "$as": return renderAs(args);
            case "$count": return renderCount(args);
            case "$sum": return renderAgg("sum", args);
            case "$avg": return renderAgg("avg", args);
            case "$max": return renderAgg("max", args);
            case "$min": return renderAgg("min", args);
            case "$eq": return renderBinary("=", args);
            case "$ne": return renderBinary("!=", args);
            case "$gt": return renderBinary(">", args);
            case "$gte": return renderBinary(">=", args);
            case "$lt": return renderBinary("<", args);
            case "$lte": return renderBinary("<=", args);
            case "$like": return renderBinary("like", args);
            case "$is": return renderIs(args);
            case "$is-not": return renderIsNot(args);
            case "$and": return renderLogical("and", args);
            case "$or": return renderLogical("or", args);
            case "$in": return renderIn(args);
            case "$case": return renderCase(args);
            case "$excluded": return renderExcluded(args);
        }
        return op.substring(1) + "(" + args.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("") + ")";
    }

    private static String renderAs(List<Object> args) {
        if (args.size() < 2) return "";
        String expr = renderExpr(args.get(0));
        String alias = renderExpr(args.get(1));
        if (args.get(0) instanceof List<?>) return "(" + expr + ") as " + alias;
        if (args.get(0) instanceof String s && isSymbolStr(s)) return s.substring(1) + " as " + alias;
        return expr + " as " + alias;
    }

    private static String renderCount(List<Object> args) {
        if (args.isEmpty()) return "count(*)";
        if (args.get(0) instanceof String s && "$*".equals(s)) return "count(*)";
        return "count(" + renderExpr(args.get(0)) + ")";
    }

    private static String renderAgg(String fn, List<Object> args) {
        if (args.isEmpty()) return fn + "(*)";
        return fn + "(" + renderExpr(args.get(0)) + ")";
    }

    private static String renderBinary(String op, List<Object> args) {
        if (args.size() < 2) return args.isEmpty() ? "" : renderExpr(args.get(0));
        return renderExpr(args.get(0)) + " " + op + " " + renderExpr(args.get(1));
    }

    private static String renderIs(List<Object> args) {
        if (args.size() < 2) return "";
        String left = renderExpr(args.get(0));
        if (args.get(1) == null) return left + " is null";
        return left + " is " + renderExpr(args.get(1));
    }

    private static String renderIsNot(List<Object> args) {
        if (args.size() < 2) return "";
        String left = renderExpr(args.get(0));
        if (args.get(1) == null) return left + " is not null";
        return left + " is not " + renderExpr(args.get(1));
    }

    private static String renderLogical(String op, List<Object> args) {
        if (args.isEmpty()) return "and".equals(op) ? "true" : "false";
        List<String> parts = new ArrayList<>();
        for (Object a : args) {
            String r = renderExpr(a);
            parts.add(isParenthesized(r) ? r : "(" + r + ")");
        }
        return "(" + String.join(" " + op + " ", parts) + ")";
    }

    @SuppressWarnings("unchecked")
    private static String renderIn(List<Object> args) {
        if (args.size() < 2) return "";
        String col = renderExpr(args.get(0));
        Object val = args.get(1);
        if (val instanceof List<?> list && isSubquery(list)) {
            return col + " in (" + renderSubquery(list) + ")";
        }
        if (val instanceof List<?> list) {
            String vals = list.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("");
            return col + " in (" + vals + ")";
        }
        return col + " in (" + renderExpr(val) + ")";
    }

    @SuppressWarnings("unchecked")
    private static String renderCase(List<Object> args) {
        List<String> parts = new ArrayList<>();
        parts.add("case");
        String elseVal = null;
        for (Object arg : args) {
            if (arg instanceof List<?> arr && !arr.isEmpty() && arr.get(0) instanceof String kw) {
                if ("$when".equals(kw) && arr.size() >= 3) {
                    parts.add("when " + renderExpr(arr.get(1)) + " then " + renderExpr(arr.get(2)));
                } else if ("$else".equals(kw) && arr.size() >= 2) {
                    elseVal = renderExpr(arr.get(1));
                }
            }
        }
        if (elseVal != null) parts.add("else " + elseVal);
        parts.add("end");
        return String.join(" ", parts);
    }

    private static String renderExcluded(List<Object> args) {
        if (args.isEmpty()) return "excluded";
        return "excluded." + renderExpr(args.get(0));
    }

    // ============================================================
    // Subquery rendering
    // ============================================================

    @SuppressWarnings("unchecked")
    private static String renderSubquery(List<?> clauses) {
        List<String> parts = new ArrayList<>();
        for (Object c : clauses) {
            if (c instanceof List<?> clause) {
                String r = renderClause((List<Object>) clause);
                if (!r.isEmpty()) parts.add(r);
            }
        }
        return String.join(" ", parts);
    }

    // ============================================================
    // Clause renderer
    // ============================================================

    private static String renderClause(List<Object> clause) {
        if (clause.isEmpty()) return "";
        Object kwObj = clause.get(0);
        if (!(kwObj instanceof String kw) || !kw.startsWith("$")) return "";
        List<Object> args = clause.subList(1, clause.size());

        switch (kw) {
            case "$select":
                return "select " + args.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("");
            case "$from":
                return "from " + renderTable(args);
            case "$join":
                return "join " + renderJoin(args);
            case "$left-join":
                return "left join " + renderJoin(args);
            case "$right-join":
                return "right join " + renderJoin(args);
            case "$full-join":
                return "full join " + renderJoin(args);
            case "$cross-join":
                return "cross join " + renderTable(args);
            case "$where":
                return args.isEmpty() ? "" : "where " + renderExpr(args.get(0));
            case "$group-by":
                return args.isEmpty() ? "" : "group by " + renderExpr(args.get(0));
            case "$having":
                return args.isEmpty() ? "" : "having " + renderExpr(args.get(0));
            case "$order-by":
                return renderOrderBy(args);
            case "$limit":
                return args.isEmpty() ? "" : "limit " + renderExpr(args.get(0));
            case "$offset":
                return args.isEmpty() ? "" : "offset " + renderExpr(args.get(0));
            case "$with":
                return renderWith(args);
            case "$insert-into":
                return renderInsertInto(args);
            case "$values":
                return "values (" + args.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("") + ")";
            case "$update":
                return "update " + renderTable(args);
            case "$set":
                return renderSet(args);
            case "$delete-from":
                return "delete from " + renderTable(args);
            case "$on-conflict":
                return args.isEmpty() ? "" : "on conflict (" + renderExpr(args.get(0)) + ")";
            case "$do-update":
                return renderDoUpdate(args);
        }
        return kw.substring(1);
    }

    @SuppressWarnings("unchecked")
    private static String renderTable(List<Object> args) {
        if (args.isEmpty()) return "";
        Object first = args.get(0);
        if (first instanceof List<?> list && !list.isEmpty() && "$as".equals(list.get(0))) {
            return renderListExpr(list);
        }
        return renderExpr(first);
    }

    private static String renderJoin(List<Object> args) {
        if (args.isEmpty()) return "";
        String table = renderExpr(args.get(0));
        if (args.size() >= 2) return table + " on " + renderExpr(args.get(1));
        return table;
    }

    private static String renderOrderBy(List<Object> args) {
        if (args.isEmpty()) return "";
        String col = renderExpr(args.get(0));
        if (args.size() >= 2 && args.get(1) instanceof String s && isSymbolStr(s)) {
            String d = s.substring(1);
            if ("desc".equals(d) || "asc".equals(d)) return "order by " + col + " " + d;
        }
        if (args.size() >= 2) return "order by " + col + " " + renderExpr(args.get(1));
        return "order by " + col;
    }

    @SuppressWarnings("unchecked")
    private static String renderWith(List<Object> args) {
        if (args.isEmpty() || !(args.get(0) instanceof Map<?, ?> map)) return "";
        Map<String, Object> cteDefs = (Map<String, Object>) map;
        List<String> cteParts = new ArrayList<>();
        for (Map.Entry<String, Object> e : cteDefs.entrySet()) {
            String cteName = isSymbolStr(e.getKey()) ? e.getKey().substring(1) : e.getKey();
            if (e.getValue() instanceof List<?> clauses && !clauses.isEmpty()) {
                List<String> innerParts = new ArrayList<>();
                for (Object c : clauses) {
                    if (c instanceof List<?> clause) {
                        String r = renderClause((List<Object>) clause);
                        if (!r.isEmpty()) innerParts.add(r);
                    }
                }
                cteParts.add(cteName + " as (" + String.join(" ", innerParts) + ")");
            }
        }
        if (cteParts.isEmpty()) return "";
        return "with " + String.join(",\n", cteParts);
    }

    private static String renderInsertInto(List<Object> args) {
        if (args.isEmpty()) return "insert into";
        String table = renderExpr(args.get(0));
        if (args.size() > 1) {
            List<String> cols = new ArrayList<>();
            for (int i = 1; i < args.size(); i++) cols.add(renderExpr(args.get(i)));
            return "insert into " + table + " (" + String.join(", ", cols) + ")";
        }
        return "insert into " + table;
    }

    @SuppressWarnings("unchecked")
    private static String renderSet(List<Object> args) {
        if (args.isEmpty() || !(args.get(0) instanceof Map<?, ?> map)) return "";
        Map<String, Object> mapping = (Map<String, Object>) map;
        List<String> parts = new ArrayList<>();
        for (Map.Entry<String, Object> e : mapping.entrySet()) {
            parts.add(renderKey(e.getKey()) + " = " + renderExpr(e.getValue()));
        }
        return "set " + String.join(", ", parts);
    }

    @SuppressWarnings("unchecked")
    private static String renderDoUpdate(List<Object> args) {
        if (args.isEmpty() || !(args.get(0) instanceof Map<?, ?> map)) return "";
        Map<String, Object> mapping = (Map<String, Object>) map;
        List<String> parts = new ArrayList<>();
        for (Map.Entry<String, Object> e : mapping.entrySet()) {
            parts.add(renderKey(e.getKey()) + " = " + renderExpr(e.getValue()));
        }
        return "do update set " + String.join(", ", parts);
    }

    // ============================================================
    // $sql functor
    // ============================================================

    @SuppressWarnings("unchecked")
    public static final FunctorBox SQL_FN = FunctorBox.box((env, args) -> {
        if (args.length == 0 || !(args[0] instanceof List<?> data)) return "";
        if (data.isEmpty()) return "";

        List<String> parts = new ArrayList<>();
        List<List<Object>> pendingValues = new ArrayList<>();
        java.util.function.Supplier<Void> flushValues = () -> {
            if (!pendingValues.isEmpty()) {
                List<String> rows = new ArrayList<>();
                for (List<Object> vlist : pendingValues) {
                    String vals = vlist.stream().map(SqlFunctors::renderExpr).reduce((a, b) -> a + ", " + b).orElse("");
                    rows.add("(" + vals + ")");
                }
                parts.add("values " + String.join(", ", rows));
                pendingValues.clear();
            }
            return null;
        };

        for (Object item : data) {
            if (!(item instanceof List<?> list) || list.isEmpty()) continue;
            Object kwObj = list.get(0);
            if ("$values".equals(kwObj)) {
                pendingValues.add(new ArrayList<>(list.subList(1, list.size())));
                continue;
            }
            flushValues.get();
            String rendered = renderClause((List<Object>) list);
            if (!rendered.isEmpty()) parts.add(rendered);
        }
        flushValues.get();

        return String.join("\n", parts);
    });

    // ============================================================
    // Legacy $query / $pattern
    // ============================================================

    public static final FunctorBox PATTERN = FunctorBox.box((env, args) -> {
        if (args.length < 3) throw new IllegalArgumentException("$pattern requires (subject, predicate, object)");
        Object subj = args[0], pred = args[1], obj = args[2];
        if (!(subj instanceof String s && pred instanceof String p && obj instanceof String o))
            throw new IllegalArgumentException("$pattern requires string arguments");
        List<String> triple = patternToTriple(s, p, o);
        return tripleToSqlCondition(triple);
    });

    public static final FunctorBox SQL_AND = FunctorBox.box((env, args) -> {
        StringBuilder result = new StringBuilder();
        for (Object arg : args) {
            Env envImpl = (Env) env;
            Object evaluated = envImpl.eval(arg);
            if (result.length() > 0) result.append(" and ");
            result.append((String) evaluated);
        }
        return result.toString();
    });

    public static final FunctorBox WILDCARD = FunctorBox.box((env, args) -> "*");

    private static final Map<String, FunctorBox> LOCAL_SQL_FUNCTORS;
    static {
        LOCAL_SQL_FUNCTORS = new LinkedHashMap<>();
        LOCAL_SQL_FUNCTORS.put("$pattern", PATTERN);
        LOCAL_SQL_FUNCTORS.put("$and", SQL_AND);
        LOCAL_SQL_FUNCTORS.put("$*", WILDCARD);
    }

    public static final FunctorBox QUERY = FunctorBox.box((env, args) -> {
        if (args.length < 1) throw new IllegalArgumentException("$query expects a condition expression");
        Env local = new Env((Env) env);
        local.load(LOCAL_SQL_FUNCTORS);
        Parser parser = new Parser(local);
        Object parsed = parser.parse(args[0]);
        AstNode condition = (AstNode) parsed;
        Object where = condition.apply(local);
        return "select " + QUERY_FIELDS + " \nfrom statement \nwhere \n    " + where + " \noffset 0\nlimit 100 \n";
    });

    public static List<String> patternToTriple(String subject, String predicate, String object) {
        List<String> pattern = new ArrayList<>(3);
        if (!"*".equals(subject) && !"$*".equals(subject)) pattern.add(subject);
        if (!"*".equals(predicate) && !"$*".equals(predicate)) pattern.add(predicate);
        if (!"*".equals(object) && !"$*".equals(object)) pattern.add(object);
        return pattern;
    }

    public static String tripleToSqlCondition(List<String> triple) {
        String json = toJson(triple);
        return "meta @> '" + json.replace("'", "''") + "'";
    }

    private static String toJson(List<String> triple) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"triple\":[");
        for (int i = 0; i < triple.size(); i++) {
            if (i > 0) sb.append(',');
            sb.append('"').append(escapeJson(triple.get(i))).append('"');
        }
        sb.append("]}");
        return sb.toString();
    }

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
                    if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
                    else sb.append(c);
                }
            }
        }
        return sb.toString();
    }

    @SuppressWarnings("unchecked")
    public static final Map<String, FunctorBox> SQL_FUNCTORS;
    static {
        SQL_FUNCTORS = new LinkedHashMap<>();
        SQL_FUNCTORS.put("$sql", SQL_FN);
        SQL_FUNCTORS.put("$query", QUERY);
    }
}
