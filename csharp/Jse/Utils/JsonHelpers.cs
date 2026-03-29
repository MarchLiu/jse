using System.Text.Json;
using System.Globalization;

namespace Jse.Utils;

public static class JsonHelpers
{
    public static object? JsonElementToObject(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Null => null,
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number => element.TryGetDecimal(out var d)
                ? d
                : decimal.Parse(element.GetRawText(), CultureInfo.InvariantCulture),
            JsonValueKind.Array => element.EnumerateArray().Select(JsonElementToObject).ToList(),
            JsonValueKind.Object => element.EnumerateObject().ToDictionary(
                p => p.Name,
                p => JsonElementToObject(p.Value)),
            _ => throw new InvalidOperationException($"Unsupported JsonValueKind: {element.ValueKind}")
        };
    }
}
