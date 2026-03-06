/**
 * Query field list for SQL SELECT.
 */
export const QUERY_FIELDS =
  "subject, predicate, object, meta";

/**
 * Convert $pattern arguments to PostgreSQL jsonb containment triple.
 * - ["$pattern", "$*", "author of", "$*"] -> triple: ["author of"]
 * - ["$pattern", "Liu Xin", "author of", "$*"] -> triple: ["Liu Xin", "author of", "$*"]
 */
export function patternToTriple(
  subject: string,
  predicate: string,
  object: string
): unknown[] {
  let pattern = [];
  if (subject !== "*") {
    pattern.push(subject);
  }
  if (predicate !== "*") {
    pattern.push(predicate);
  }
  if (object !== "*") {
    pattern.push(object);
  }
  return pattern;
}

/**
 * Build SQL WHERE clause for a triple pattern.
 */
export function tripleToSqlCondition(triple: unknown[]): string {
  const json = JSON.stringify({ triple });
  const escaped = json.replace(/'/g, "''");
  return `meta @> '${escaped}'`;
}
