using System.Linq.Expressions;
using System.Text.Json;
using System.Text.Json.Serialization;
using Jse.Ast;
using Jse.Runtime;
using Jse.Utils;

namespace Jse.Serialization;

public static class JseRuntimeSerializer
{
    private static readonly JsonSerializerOptions JsonOptions = new();

    public static JseNode DeserializeNode(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        using var doc = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 2048 });
        return ParseElement(doc.RootElement);
    }

    public static JseNode DeserializeNode(JsonElement element) => ParseElement(element);

    public static string SerializeNode(JseNode node)
    {
        ArgumentNullException.ThrowIfNull(node);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            WriteNode(writer, node);
        }

        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }

    public static string SerializeOperatorSettings(OperatorEnvironment settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var dto = new OperatorSettingsDto
        {
            Operators = settings.Operators.Snapshot()
                .SelectMany(static pair => pair.Value)
                .Select(CreateBindingDto)
                .ToList()
        };

        return JsonSerializer.Serialize(dto, JsonOptions);
    }

    public static OperatorEnvironment DeserializeOperatorSettings(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);

        var dto = JsonSerializer.Deserialize<OperatorSettingsDto>(json, JsonOptions)
            ?? throw new InvalidOperationException("Failed to deserialize operator settings.");

        var registry = new OperatorRegistry();
        foreach (var binding in dto.Operators)
        {
            switch (binding)
            {
                case ExpressionOperatorBindingDto expressionBinding:
                {
                    var lambda = JseCsharpOperatorExpressionCodec.Deserialize(expressionBinding.Expression);
                    registry.RegisterExpression(expressionBinding.Name, lambda);
                    break;
                }

                default:
                    throw new NotSupportedException($"Unsupported serialized operator binding type: {binding.GetType().Name}.");
            }
        }

        return new OperatorEnvironment(registry);
    }

    private static JseNode ParseElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Array => ParseArray(element),
            JsonValueKind.Object => ParseObject(element),
            JsonValueKind.String => ParseString(element.GetString() ?? string.Empty),
            _ => new JseLiteral(JsonHelpers.JsonElementToObject(element))
        };
    }

    private static JseNode ParseArray(JsonElement array)
    {
        var items = array.EnumerateArray().ToList();
        if (items.Count > 0 && items[0].ValueKind == JsonValueKind.String)
        {
            var head = items[0].GetString() ?? string.Empty;
            if (IsSymbol(head))
            {
                var op = NormalizeSymbol(head);
                var args = items.Skip(1).Select(ParseElement).ToList();
                return new JseCall(op, args);
            }
        }

        var literalList = items.Select(JsonHelpers.JsonElementToObject).ToList();
        return new JseLiteral(literalList);
    }

    private static JseNode ParseObject(JsonElement obj)
    {
        var props = obj.EnumerateObject().ToList();
        var symbolProps = props.Where(p => IsSymbol(p.Name)).ToList();

        if (symbolProps.Count > 1)
        {
            throw new InvalidOperationException("JSE_STRUCTURE_ERROR: object expression must contain exactly one symbol key.");
        }

        if (symbolProps.Count == 1)
        {
            var opProp = symbolProps[0];
            var op = NormalizeSymbol(opProp.Name);

            var args = opProp.Value.ValueKind == JsonValueKind.Array
                ? opProp.Value.EnumerateArray().Select(ParseElement).ToList()
                : new List<JseNode> { ParseElement(opProp.Value) };

            var meta = props
                .Where(p => p.Name != opProp.Name)
                .ToDictionary(p => p.Name, p => JsonHelpers.JsonElementToObject(p.Value));

            return new JseCall(op, args, meta.Count == 0 ? null : meta);
        }

        var literalObj = props.ToDictionary(p => p.Name, p => JsonHelpers.JsonElementToObject(p.Value));
        return new JseLiteral(literalObj);
    }

    private static JseNode ParseString(string value)
    {
        if (value.StartsWith("$$", StringComparison.Ordinal))
        {
            return new JseLiteral(value[1..]);
        }

        if (IsSymbol(value))
        {
            return new JseSymbol(NormalizeSymbol(value));
        }

        return new JseLiteral(value);
    }

    private static bool IsSymbol(string value) =>
        value != "$*" && value.StartsWith('$') && !value.StartsWith("$$", StringComparison.Ordinal);

    private static string NormalizeSymbol(string value) =>
        value.StartsWith('$') ? value[1..] : value;

    private static void WriteNode(Utf8JsonWriter writer, JseNode node)
    {
        switch (node)
        {
            case JseLiteral literal:
                WriteValue(writer, literal.Value, new HashSet<object>(ReferenceEqualityComparer.Instance));
                break;

            case JseSymbol symbol:
                writer.WriteStringValue($"${symbol.Name}");
                break;

            case JseCall call when call.Meta is null || call.Meta.Count == 0:
                writer.WriteStartArray();
                writer.WriteStringValue($"${call.Operator}");
                foreach (var arg in call.Args)
                {
                    WriteNode(writer, arg);
                }

                writer.WriteEndArray();
                break;

            case JseCall call:
                writer.WriteStartObject();
                writer.WritePropertyName($"${call.Operator}");
                writer.WriteStartArray();
                foreach (var arg in call.Args)
                {
                    WriteNode(writer, arg);
                }

                writer.WriteEndArray();

                var meta = call.Meta ?? new Dictionary<string, object?>();
                foreach (var kv in meta)
                {
                    writer.WritePropertyName(kv.Key);
                    WriteValue(writer, kv.Value, new HashSet<object>(ReferenceEqualityComparer.Instance));
                }

                writer.WriteEndObject();

                break;

            default:
                throw new InvalidOperationException($"Unsupported AST node: {node.GetType().Name}");
        }
    }

    private static void WriteValue(Utf8JsonWriter writer, object? value, HashSet<object> visited)
    {
        switch (value)
        {
            case null:
                writer.WriteNullValue();
                return;

            case string s:
                writer.WriteStringValue(s);
                return;

            case bool b:
                writer.WriteBooleanValue(b);
                return;

            case byte v:
                writer.WriteNumberValue(v);
                return;

            case sbyte v:
                writer.WriteNumberValue(v);
                return;

            case short v:
                writer.WriteNumberValue(v);
                return;

            case ushort v:
                writer.WriteNumberValue(v);
                return;

            case int v:
                writer.WriteNumberValue(v);
                return;

            case uint v:
                writer.WriteNumberValue(v);
                return;

            case long v:
                writer.WriteNumberValue(v);
                return;

            case ulong v:
                writer.WriteNumberValue(v);
                return;

            case float v:
                writer.WriteNumberValue(v);
                return;

            case double v:
                writer.WriteNumberValue(v);
                return;

            case decimal v:
                writer.WriteNumberValue(v);
                return;

            case JsonElement element:
                element.WriteTo(writer);
                return;

            case JseNode node:
                WriteNode(writer, node);
                return;
        }

        if (value is IDictionary<string, object?> dict)
        {
            EnsureNotVisited(visited, value);
            writer.WriteStartObject();
            foreach (var kv in dict)
            {
                writer.WritePropertyName(kv.Key);
                WriteValue(writer, kv.Value, visited);
            }

            writer.WriteEndObject();
            visited.Remove(value);
            return;
        }

        if (value is IEnumerable<object?> list)
        {
            EnsureNotVisited(visited, value);
            writer.WriteStartArray();
            foreach (var item in list)
            {
                WriteValue(writer, item, visited);
            }

            writer.WriteEndArray();
            visited.Remove(value);
            return;
        }

        JsonSerializer.Serialize(writer, value, value.GetType(), JsonOptions);
    }

    private static void EnsureNotVisited(HashSet<object> visited, object value)
    {
        if (!visited.Add(value))
        {
            throw new JsonException("Cycle detected while serializing runtime value.");
        }
    }

    private static OperatorBindingDto CreateBindingDto(OperatorBinding binding)
    {
        if (binding.ExpressionDefinition is not null)
        {
            return new ExpressionOperatorBindingDto
            {
                Name = binding.Name,
                Expression = JseCsharpOperatorExpressionCodec.Serialize(binding.ExpressionDefinition)
            };
        }

        throw new NotSupportedException(
            $"Operator '{binding.Name}' is not expression-backed. Expression-only serialization is enabled.");
    }

    private static string GetTypeId(Type type) =>
        type.AssemblyQualifiedName
        ?? throw new InvalidOperationException($"Type '{type.FullName}' has no assembly-qualified name.");

    private static Type ResolveType(string typeId) =>
        Type.GetType(typeId, throwOnError: false)
        ?? throw new InvalidOperationException($"Unable to resolve type '{typeId}'.");

    private sealed class OperatorSettingsDto
    {
        public List<OperatorBindingDto> Operators { get; set; } = [];
    }

    [JsonPolymorphic(TypeDiscriminatorPropertyName = "$kind")]
    [JsonDerivedType(typeof(ExpressionOperatorBindingDto), typeDiscriminator: "expression")]
    private abstract class OperatorBindingDto
    {
        public required string Name { get; set; }
    }

    private sealed class ExpressionOperatorBindingDto : OperatorBindingDto
    {
        public required JseCsharpOperatorLambdaNode Expression { get; set; }
    }
}
