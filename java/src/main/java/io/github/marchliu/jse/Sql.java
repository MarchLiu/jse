package io.github.marchliu.jse;

import java.util.List;

/**
 * SQL helpers for JSE query expressions.
 *
 * <p>This class now delegates to {@link io.github.marchliu.jse.functors.SqlFunctors}
 * for the actual implementation.</p>
 *
 * @deprecated Use {@link io.github.marchliu.jse.functors.SqlFunctors} directly.
 */
@Deprecated
public final class Sql {
    private Sql() {}

    /** Query field list for SQL SELECT. */
    public static final String QUERY_FIELDS = io.github.marchliu.jse.functors.SqlFunctors.QUERY_FIELDS;

    /**
     * Convert $pattern arguments to PostgreSQL jsonb containment triple.
     * <ul>
     *   <li>["*", "author of", "*"] -> ["author of"]</li>
     *   <li>["Liu Xin", "author of", "*"] -> ["Liu Xin", "author of", "*"]</li>
     * </ul>
     *
     * @param subject   Subject pattern
     * @param predicate Predicate pattern
     * @param object    Object pattern
     * @return List of non-wildcard elements
     * @deprecated Use {@link io.github.marchliu.jse.functors.SqlFunctors#patternToTriple(String, String, String)}
     */
    @Deprecated
    public static List<String> patternToTriple(String subject, String predicate, String object) {
        return io.github.marchliu.jse.functors.SqlFunctors.patternToTriple(subject, predicate, object);
    }

    /**
     * Build SQL WHERE clause for a triple pattern.
     *
     * @param triple Triple list
     * @return SQL WHERE condition
     * @deprecated Use {@link io.github.marchliu.jse.functors.SqlFunctors#tripleToSqlCondition(List)}
     */
    @Deprecated
    public static String tripleToSqlCondition(List<String> triple) {
        return io.github.marchliu.jse.functors.SqlFunctors.tripleToSqlCondition(triple);
    }
}
