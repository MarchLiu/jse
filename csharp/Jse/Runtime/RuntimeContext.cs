using Jse.Ast;

namespace Jse.Runtime;

public sealed class RuntimeContext
{
    public RuntimeContext(OperatorEnvironment environment, RuntimeScope scope)
    {
        Environment = environment;
        Scope = scope;
    }

    public OperatorEnvironment Environment { get; }

    public RuntimeScope Scope { get; }
}

public static class RuntimeEvaluator
{
    public static object? QuoteNode(JseNode node)
    {
        ArgumentNullException.ThrowIfNull(node);

        return node switch
        {
            JseLiteral literal => literal.Value,
            JseSymbol symbol => $"${symbol.Name}",
            JseCall call when call.Meta is not null && call.Meta.Count > 0 => QuoteCallAsObject(call),
            JseCall call => new object?[]
            {
                $"${call.Operator}"
            }.Concat(call.Args.Select(QuoteNode)).ToList(),
            _ => throw new InvalidOperationException($"Unsupported quoted AST node: {node.GetType().Name}")
        };
    }

    public static object? EvaluateNode(JseNode node, RuntimeContext context)
    {
        ArgumentNullException.ThrowIfNull(node);
        ArgumentNullException.ThrowIfNull(context);

        return node switch
        {
            JseLiteral literal => literal.Value,
            JseSymbol symbol => ResolveSymbol(symbol.Name, context),
            JseCall call => EvaluateCall(call, context),
            _ => throw new InvalidOperationException($"Unsupported AST node: {node.GetType().Name}")
        };
    }

    private static object? ResolveSymbol(string name, RuntimeContext context)
    {
        if (context.Scope.TryResolve(name, out var value))
        {
            return value;
        }

        throw new KeyNotFoundException($"SymbolNotFound: ${name}");
    }

    private static Dictionary<string, object?> QuoteCallAsObject(JseCall call)
    {
        var result = new Dictionary<string, object?>
        {
            [$"${call.Operator}"] = call.Args.Select(QuoteNode).ToList()
        };

        foreach (var kv in call.Meta!)
        {
            result[kv.Key] = kv.Value;
        }

        return result;
    }

    private static object? EvaluateCall(JseCall call, RuntimeContext context)
    {
        if (context.Environment.Operators.TryResolveSpecial(call.Operator, out var special))
        {
            return special(context, call.Args);
        }

        if (context.Scope.TryResolve(call.Operator, out var scopedValue) && scopedValue is IRuntimeCallable callable)
        {
            var scopedArgs = call.Args.Select(arg => EvaluateNode(arg, context)).ToList();
            return callable.Invoke(context, scopedArgs);
        }

        var values = call.Args.Select(arg => EvaluateNode(arg, context)).ToList();

        if (context.Environment.Operators.TryResolveVariadic(call.Operator, out var variadic))
        {
            return variadic(values);
        }

        var valueTypes = values.Select(static value => value?.GetType() ?? typeof(object)).ToArray();
        var binding = context.Environment.Operators.Resolve(call.Operator, valueTypes);

        var convertedArgs = values
            .Select((value, i) => ConvertRuntimeValue(value, binding.ParameterTypes[i]))
            .ToArray();

        return binding.Implementation.DynamicInvoke(convertedArgs);
    }

    private static object? ConvertRuntimeValue(object? value, Type targetType)
    {
        if (value is null)
        {
            return null;
        }

        var sourceType = value.GetType();
        if (targetType.IsAssignableFrom(sourceType))
        {
            return value;
        }

        if (targetType == typeof(object))
        {
            return value;
        }

        return Convert.ChangeType(value, targetType);
    }

    public static object? InvokeByValue(RuntimeContext context, object? functor, IReadOnlyList<object?> values)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(values);

        if (functor is IRuntimeCallable callable)
        {
            return callable.Invoke(context, values);
        }

        if (functor is string symbol)
        {
            var normalized = NormalizeName(symbol);

            if (context.Scope.TryResolve(normalized, out var scopedValue) && scopedValue is IRuntimeCallable scopedCallable)
            {
                return scopedCallable.Invoke(context, values);
            }

            if (context.Environment.Operators.TryResolveVariadic(normalized, out var variadic))
            {
                return variadic(values);
            }

            var argTypes = values.Select(static value => value?.GetType() ?? typeof(object)).ToArray();
            var binding = context.Environment.Operators.Resolve(normalized, argTypes);
            var converted = values
                .Select((value, i) => ConvertRuntimeValue(value, binding.ParameterTypes[i]))
                .ToArray();
            return binding.Implementation.DynamicInvoke(converted);
        }

        throw new InvalidOperationException("$apply first argument must be callable or symbol.");
    }

    public static JseNode ParseRuntimeExpression(object? value)
    {
        return value switch
        {
            null => new JseLiteral(null),
            JseNode node => node,
            string s when IsSymbol(s) => new JseSymbol(NormalizeName(s)),
            string s => new JseLiteral(s),
            bool b => new JseLiteral(b),
            decimal d => new JseLiteral(d),
            long l => new JseLiteral(l),
            int i => new JseLiteral(i),
            double d => new JseLiteral(d),
            List<object?> list => ParseRuntimeList(list),
            Dictionary<string, object?> dict => ParseRuntimeMap(dict),
            _ => new JseLiteral(value)
        };
    }

    private static JseNode ParseRuntimeList(IReadOnlyList<object?> list)
    {
        if (list.Count > 0 && list[0] is string symbol && IsSymbol(symbol))
        {
            var op = NormalizeName(symbol);
            var args = list.Skip(1).Select(ParseRuntimeExpression).ToList();
            return new JseCall(op, args);
        }

        return new JseLiteral(list.ToList());
    }

    private static JseNode ParseRuntimeMap(IReadOnlyDictionary<string, object?> map)
    {
        var symbolEntries = map.Where(static pair => IsSymbol(pair.Key)).ToList();
        if (symbolEntries.Count == 1)
        {
            var pair = symbolEntries[0];
            var op = NormalizeName(pair.Key);
            var args = pair.Value is List<object?> arr
                ? arr.Select(ParseRuntimeExpression).ToList()
                : new List<JseNode> { ParseRuntimeExpression(pair.Value) };
            return new JseCall(op, args);
        }

        return new JseLiteral(map.ToDictionary(static pair => pair.Key, static pair => pair.Value));
    }

    private static bool IsSymbol(string value) =>
        value != "$*" && value.StartsWith('$') && !value.StartsWith("$$", StringComparison.Ordinal);

    public static string NormalizeName(string value) =>
        value.StartsWith('$') ? value[1..] : value;
}