namespace Jse.Runtime.Functors;

public static class DefaultFunctors
{
    public static bool Eq(object? left, object? right) => Equals(left, right);

    public static bool Eq1(object? _) => true;

    public static bool Eq3(object? a, object? b, object? c) => Equals(a, b) && Equals(b, c);

    public static bool EqVariadic(IReadOnlyList<object?> args)
    {
        if (args.Count <= 1)
        {
            return true;
        }

        for (var i = 0; i < args.Count - 1; i++)
        {
            if (!Equals(args[i], args[i + 1]))
            {
                return false;
            }
        }

        return true;
    }

    public static object? Head(List<object?> list)
    {
        ArgumentNullException.ThrowIfNull(list);
        if (list.Count == 0)
        {
            throw new InvalidOperationException("$head requires non-empty list.");
        }

        return list[0];
    }

    public static List<object?> Tail(List<object?> list)
    {
        ArgumentNullException.ThrowIfNull(list);
        if (list.Count <= 1)
        {
            return new List<object?>();
        }

        return list.Skip(1).ToList();
    }

    public static bool Atom(object? value) =>
        value is null or string or bool or decimal;

    public static List<object?> Cons(object? value, List<object?> list)
    {
        ArgumentNullException.ThrowIfNull(list);
        var result = new List<object?>(list.Count + 1) { value };
        result.AddRange(list);
        return result;
    }

    public static bool Not(object? value) => !IsTruthy(value);

    public static bool ListP(object? value) => value is List<object?>;

    public static bool MapP(object? value) => value is Dictionary<string, object?>;

    public static bool NullP(object? value) => value is null;

    public static bool NullP0() => true;

    public static object? Get(Dictionary<string, object?> map, string key)
    {
        ArgumentNullException.ThrowIfNull(map);
        ArgumentNullException.ThrowIfNull(key);
        return map.TryGetValue(key, out var value) ? value : null;
    }

    public static object? Get(List<object?> list, decimal index)
    {
        ArgumentNullException.ThrowIfNull(list);
        return list[ToIndex(index, list.Count)];
    }

    public static Dictionary<string, object?> Set(Dictionary<string, object?> map, string key, object? value)
    {
        ArgumentNullException.ThrowIfNull(map);
        ArgumentNullException.ThrowIfNull(key);
        map[key] = value;
        return map;
    }

    public static List<object?> Set(List<object?> list, decimal index, object? value)
    {
        ArgumentNullException.ThrowIfNull(list);
        list[ToIndex(index, list.Count)] = value;
        return list;
    }

    public static Dictionary<string, object?> Del(Dictionary<string, object?> map, string key)
    {
        ArgumentNullException.ThrowIfNull(map);
        ArgumentNullException.ThrowIfNull(key);
        map.Remove(key);
        return map;
    }

    public static List<object?> Del(List<object?> list, decimal index)
    {
        ArgumentNullException.ThrowIfNull(list);
        list.RemoveAt(ToIndex(index, list.Count));
        return list;
    }

    public static List<object?> Conj(object? value, List<object?> list)
    {
        ArgumentNullException.ThrowIfNull(list);
        var result = new List<object?>(list.Count + 1);
        result.AddRange(list);
        result.Add(value);
        return result;
    }

    public static bool AndVariadic(IReadOnlyList<object?> args) => args.All(IsTruthy);

    public static bool OrVariadic(IReadOnlyList<object?> args) => args.Any(IsTruthy);

    private static bool IsTruthy(object? value)
    {
        return value switch
        {
            null => false,
            bool b => b,
            _ => true
        };
    }

    private static int ToIndex(decimal index, int length)
    {
        if (index != decimal.Truncate(index))
        {
            throw new InvalidOperationException("List index must be an integer.");
        }

        if (index < 0 || index >= length)
        {
            throw new InvalidOperationException($"Index {index} out of range for list of length {length}.");
        }

        return decimal.ToInt32(index);
    }
}