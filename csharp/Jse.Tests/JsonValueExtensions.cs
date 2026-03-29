using System.Globalization;
using System.Text.Json;
using Jse.Utils;

namespace Jse.Tests;

public static class JsonValueExtensions
{
    public static object? JsonValue<T>(this T value)
        where T : struct
    {
        return value switch
        {
            bool b => b,
            byte or sbyte or short or ushort or int or uint or long => Convert.ToDecimal(value, CultureInfo.InvariantCulture),
            float or double or decimal => Convert.ToDecimal(value, CultureInfo.InvariantCulture),
            _ => JsonFromText(JsonSerializer.Serialize(value.ToString()))
        };
    }

    private static object? JsonFromText(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return JsonHelpers.JsonElementToObject(doc.RootElement);
    }
}
