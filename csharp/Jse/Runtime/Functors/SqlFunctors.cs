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
}