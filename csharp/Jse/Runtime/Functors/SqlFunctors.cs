using System.Data;
using System.Text.Json.Nodes;
using Jse.Ast;

namespace Jse.Runtime.Functors;

public sealed record SqlQueryParameter(
    string Name,
    SqlDbType DbType,
    string JsonText,
    JsonNode ParsedValue);

public sealed record SqlQueryPlan(
    string SqlText,
    IReadOnlyList<SqlQueryParameter> Parameters);

public static class SqlFunctors
{
    public const string QueryFields = "subject, predicate, object, meta";

    public static SqlQueryPlan Query(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        if (args.Count < 1)
        {
            throw new InvalidOperationException("$query expects a condition expression.");
        }

        var payloads = new List<(SqlDbType DbType, string JsonText, JsonNode ParsedValue)>();
        var conditionValue = RuntimeEvaluator.EvaluateNode(args[0], context);
        var where = EvaluateCondition(conditionValue, payloads);

        var sql = $"select {QueryFields} \nfrom statement \nwhere \n    {where} \noffset 0\nlimit 100 \n";
        var parameters = payloads
            .Select((entry, i) => new SqlQueryParameter($"p{i}", entry.DbType, entry.JsonText, entry.ParsedValue))
            .ToList();

        return new SqlQueryPlan(sql, parameters);
    }

    private static string EvaluateCondition(
        object? expr,
        List<(SqlDbType DbType, string JsonText, JsonNode ParsedValue)> payloads)
    {
        if (expr is List<object?> list && list.Count > 0 && list[0] is string op)
        {
            var name = RuntimeEvaluator.NormalizeName(op);
            return name switch
            {
                "and" => SqlAnd(list.Skip(1).ToList(), payloads),
                "pattern" => Pattern(list.Skip(1).ToList(), payloads),
                _ => throw new InvalidOperationException($"Unsupported local query operator '${name}'.")
            };
        }

        if (expr is Dictionary<string, object?> map)
        {
            var symbolEntries = map.Where(static p => p.Key.StartsWith('$')).ToList();
            if (symbolEntries.Count == 1)
            {
                var pair = symbolEntries[0];
                var opName = pair.Key;
                var args = pair.Value is List<object?> arr ? arr : new List<object?> { pair.Value };
                var call = new List<object?> { opName };
                call.AddRange(args);
                return EvaluateCondition(call, payloads);
            }
        }

        throw new InvalidOperationException("$query condition must evaluate to a query expression.");
    }

    private static string SqlAnd(
        IReadOnlyList<object?> args,
        List<(SqlDbType DbType, string JsonText, JsonNode ParsedValue)> payloads)
    {
        var tokens = args.Select(arg => EvaluateCondition(arg, payloads)).ToList();
        return string.Join(" and ", tokens);
    }

    private static string Pattern(
        IReadOnlyList<object?> args,
        List<(SqlDbType DbType, string JsonText, JsonNode ParsedValue)> payloads)
    {
        if (args.Count < 3)
        {
            throw new InvalidOperationException("$pattern requires (subject, predicate, object).");
        }

        var subject = ArgAsString(args[0]);
        var predicate = ArgAsString(args[1]);
        var obj = ArgAsString(args[2]);

        var triple = PatternToTripleForQuery(subject, predicate, obj);
        var payloadNode = BuildJsonPayloadNode(triple);
        var dbType = InferSqlDbType(payloadNode);
        var json = payloadNode.ToJsonString();
        payloads.Add((dbType, json, payloadNode));

        var index = payloads.Count - 1;
        return $"meta @> CAST(@p{index} AS jsonb)";
    }

    private static string ArgAsString(object? value)
    {
        return value as string
            ?? throw new InvalidOperationException("$pattern requires string arguments.");
    }

    private static List<string> PatternToTripleForQuery(string subject, string predicate, string obj)
    {
        if (subject == "$*" && predicate == "$*" && obj == "$*")
        {
            return PatternToTriple(subject, predicate, obj);
        }

        var triple = new List<string>(3);

        if (subject == "$*")
        {
            triple.Add("*");
        }
        else if (!string.IsNullOrEmpty(subject))
        {
            triple.Add(subject);
        }

        if (predicate == "$*")
        {
            triple.Add("*");
        }
        else if (!string.IsNullOrEmpty(predicate))
        {
            triple.Add(predicate);
        }

        if (obj == "$*")
        {
            triple.Add("*");
        }
        else if (!string.IsNullOrEmpty(obj))
        {
            triple.Add(obj);
        }

        return triple;
    }

    private static List<string> PatternToTriple(string subject, string predicate, string obj)
    {
        var triple = new List<string>(3);

        if (subject != "$*" && !string.IsNullOrEmpty(subject))
        {
            triple.Add(subject);
        }

        if (predicate != "$*" && !string.IsNullOrEmpty(predicate))
        {
            triple.Add(predicate);
        }

        if (obj != "$*" && !string.IsNullOrEmpty(obj))
        {
            triple.Add(obj);
        }

        return triple;
    }

    private static JsonNode BuildJsonPayloadNode(IReadOnlyList<string> triple)
    {
        return new JsonObject
        {
            ["triple"] = new JsonArray(triple.Select(static t => (JsonNode?)JsonValue.Create(t)).ToArray())
        };
    }

    private static SqlDbType InferSqlDbType(JsonNode node)
    {
        if (node is JsonValue value)
        {
            if (value.TryGetValue<bool>(out _))
            {
                return SqlDbType.Bit;
            }

            if (value.TryGetValue<int>(out _) || value.TryGetValue<long>(out _))
            {
                return SqlDbType.BigInt;
            }

            if (value.TryGetValue<float>(out _) || value.TryGetValue<double>(out _) || value.TryGetValue<decimal>(out _))
            {
                return SqlDbType.Decimal;
            }

            if (value.TryGetValue<string>(out _))
            {
                return SqlDbType.NVarChar;
            }
        }

        return SqlDbType.NVarChar;
    }

    public static string Sql(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        if (args.Count == 0) return "";
        var rawValue = RuntimeEvaluator.EvaluateNode(args[0], context);
        if (rawValue is not List<object?> clauses) return "";
        var parts = new List<string>();
        var pendingValues = new List<List<object?>>();

        void FlushValues()
        {
            if (pendingValues.Count > 0)
            {
                var rows = pendingValues.Select(vlist =>
                    $"({string.Join(", ", vlist.Select(SqlRenderExpr))})");
                parts.Add($"values {string.Join(", ", rows)}");
                pendingValues.Clear();
            }
        }

        foreach (var item in clauses)
        {
            if (item is not List<object?> clause || clause.Count == 0) continue;
            var kw = clause[0] as string;
            if (kw == "$values")
            {
                pendingValues.Add(clause.Skip(1).ToList()!);
                continue;
            }
            FlushValues();
            var rendered = SqlRenderClause(clause);
            if (!string.IsNullOrEmpty(rendered)) parts.Add(rendered);
        }
        FlushValues();
        return string.Join("\n", parts);
    }

    private static string SqlRenderExpr(object? value) => value switch
    {
        null => "null",
        bool b => b ? "true" : "false",
        int or long or double or float or decimal => value.ToString()!,
        string s when s.StartsWith("$$") => $"'{SqlQuote("$" + s[2..])}'",
        string s when s.StartsWith('$') && !s.StartsWith("$$") && s != "$*" => s[1..],
        string s => $"'{SqlQuote(s)}'",
        List<object?> list => list.Count == 0 ? "" :
            list[0] is string op && op.StartsWith('$') && !op.StartsWith("$$")
                ? SqlRenderFunc(op, list.Skip(1).ToList()!)
                : string.Join(", ", list.Select(SqlRenderExpr)),
        Dictionary<string, object?> dict => SqlRenderDict(dict),
        _ => value?.ToString() ?? ""
    };

    private static string SqlQuote(string s) => s.Replace("'", "''");

    private static string SqlRenderDict(Dictionary<string, object?> d)
    {
        if (d.Count == 0) return "";
        var parts = d.Select(kv => $"{SqlRenderKey(kv.Key)} = {SqlRenderExpr(kv.Value)}");
        return string.Join(", ", parts);
    }

    private static string SqlRenderKey(string k) =>
        k.StartsWith('$') && !k.StartsWith("$$") ? k[1..] : k.StartsWith("$$") ? "$" + k[2..] : k;

    private static string SqlRenderFunc(string op, List<object?> args) => op switch
    {
        "$as" => args.Count < 2 ? "" : args[0] is List<object?> ? $"({SqlRenderExpr(args[0])}) as {SqlRenderExpr(args[1])}" :
            args[0] is string s && s.StartsWith('$') ? $"{s[1..]} as {SqlRenderExpr(args[1])}" : $"{SqlRenderExpr(args[0])} as {SqlRenderExpr(args[1])}",
        "$count" => args.Count == 0 || (args[0] is string cs && cs == "$*") ? "count(*)" : $"count({SqlRenderExpr(args[0])})",
        "$sum" => $"sum({(args.Count > 0 ? SqlRenderExpr(args[0]) : "*")})",
        "$avg" => $"avg({(args.Count > 0 ? SqlRenderExpr(args[0]) : "*")})",
        "$max" => $"max({(args.Count > 0 ? SqlRenderExpr(args[0]) : "*")})",
        "$min" => $"min({(args.Count > 0 ? SqlRenderExpr(args[0]) : "*")})",
        "$eq" or "$ne" or "$gt" or "$gte" or "$lt" or "$lte" or "$like" =>
            args.Count < 2 ? "" : $"{SqlRenderExpr(args[0])} {op[1..].Replace("like","like")} {SqlRenderExpr(args[1])}",
        "$is" => args.Count < 2 ? "" : args[1] is null ? $"{SqlRenderExpr(args[0])} is null" : $"{SqlRenderExpr(args[0])} is {SqlRenderExpr(args[1])}",
        "$is-not" => args.Count < 2 ? "" : args[1] is null ? $"{SqlRenderExpr(args[0])} is not null" : $"{SqlRenderExpr(args[0])} is not {SqlRenderExpr(args[1])}",
        "$excluded" => args.Count == 0 ? "excluded" : $"excluded.{SqlRenderExpr(args[0])}",
        _ => $"{op[1..]}({string.Join(", ", args.Select(SqlRenderExpr))})"
    };

    private static string SqlRenderClause(List<object?> clause)
    {
        if (clause.Count == 0 || clause[0] is not string kw) return "";
        var args = clause.Skip(1).ToList()!;
        return kw switch
        {
            "$select" => $"select {string.Join(", ", args.Select(SqlRenderExpr))}",
            "$from" => $"from {SqlRenderTable(args)}",
            "$join" => $"join {SqlRenderJoin(args)}",
            "$left-join" => $"left join {SqlRenderJoin(args)}",
            "$right-join" => $"right join {SqlRenderJoin(args)}",
            "$full-join" => $"full join {SqlRenderJoin(args)}",
            "$cross-join" => $"cross join {SqlRenderTable(args)}",
            "$where" => args.Count > 0 ? $"where {SqlRenderExpr(args[0])}" : "",
            "$group-by" => args.Count > 0 ? $"group by {SqlRenderExpr(args[0])}" : "",
            "$having" => args.Count > 0 ? $"having {SqlRenderExpr(args[0])}" : "",
            "$order-by" => SqlRenderOrderBy(args),
            "$limit" => args.Count > 0 ? $"limit {SqlRenderExpr(args[0])}" : "",
            "$offset" => args.Count > 0 ? $"offset {SqlRenderExpr(args[0])}" : "",
            "$insert-into" => SqlRenderInsertInto(args),
            "$values" => $"values ({string.Join(", ", args.Select(SqlRenderExpr))})",
            "$update" => $"update {SqlRenderTable(args)}",
            "$set" => SqlRenderSet(args),
            "$delete-from" => $"delete from {SqlRenderTable(args)}",
            "$on-conflict" => args.Count > 0 ? $"on conflict ({SqlRenderExpr(args[0])})" : "",
            _ => kw[1..]
        };
    }

    private static string SqlRenderTable(List<object?> args) =>
        args.Count == 0 ? "" : args[0] is List<object?> l && l.Count > 0 && l[0] is string lop && lop == "$as"
            ? SqlRenderFunc("$as", l.Skip(1).ToList()!) : SqlRenderExpr(args[0]);

    private static string SqlRenderJoin(List<object?> args) =>
        args.Count == 0 ? "" : args.Count >= 2 ? $"{SqlRenderExpr(args[0])} on {SqlRenderExpr(args[1])}" : SqlRenderExpr(args[0]);

    private static string SqlRenderOrderBy(List<object?> args)
    {
        if (args.Count == 0) return "";
        var col = SqlRenderExpr(args[0]);
        if (args.Count >= 2 && args[1] is string d && d.StartsWith('$'))
        {
            var dir = d[1..];
            if (dir is "desc" or "asc") return $"order by {col} {dir}";
        }
        return args.Count >= 2 ? $"order by {col} {SqlRenderExpr(args[1])}" : $"order by {col}";
    }

    private static string SqlRenderInsertInto(List<object?> args)
    {
        if (args.Count == 0) return "insert into";
        var table = SqlRenderExpr(args[0]);
        if (args.Count > 1) return $"insert into {table} ({string.Join(", ", args.Skip(1).Select(SqlRenderExpr))})";
        return $"insert into {table}";
    }

    private static string SqlRenderSet(List<object?> args) =>
        args.Count == 0 || args[0] is not Dictionary<string, object?> map ? "" :
        $"set {string.Join(", ", map.Select(kv => $"{SqlRenderKey(kv.Key)} = {SqlRenderExpr(kv.Value)}"))}";
}
