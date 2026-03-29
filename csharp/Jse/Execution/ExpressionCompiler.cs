using System.Collections.Concurrent;
using System.Linq.Expressions;
using Jse.Ast;
using Jse.Runtime;

namespace Jse.Execution;

public sealed class ExpressionCompiler
{
    private readonly ConcurrentDictionary<string, Delegate> _cache = new(StringComparer.Ordinal);

    public Func<object?> Compile(JseNode ast, OperatorEnvironment settings)
    {
        return Compile<object?>(ast, settings);
    }

    public Func<T> Compile<T>(JseNode ast, OperatorEnvironment settings)
    {
        var key = $"{typeof(T).FullName}:{BuildCacheKey(ast)}";
        return (Func<T>)_cache.GetOrAdd(key, _ => BuildDelegate<T>(ast, settings));
    }

    private static Func<T> BuildDelegate<T>(JseNode ast, OperatorEnvironment settings)
    {
        var context = new RuntimeContext(settings, settings.GlobalScope);
        var evaluateMethod = typeof(RuntimeEvaluator).GetMethod(nameof(RuntimeEvaluator.EvaluateNode))
            ?? throw new InvalidOperationException("Runtime evaluator entry point was not found.");
        var body = Expression.Call(
            evaluateMethod,
            Expression.Constant(ast, typeof(JseNode)),
            Expression.Constant(context, typeof(RuntimeContext)));
        var lambda = Expression.Lambda<Func<T>>(ConvertIfNeeded(body, typeof(T)));
        return lambda.Compile();
    }

    private static Expression ConvertIfNeeded(Expression expression, Type targetType)
    {
        if (expression.Type == targetType)
        {
            return expression;
        }

        if (targetType.IsAssignableFrom(expression.Type) && !expression.Type.IsValueType)
        {
            return expression;
        }

        return Expression.Convert(expression, targetType);
    }

    private static string BuildCacheKey(JseNode ast) => SerializeNode(ast);

    private static string SerializeNode(JseNode node)
    {
        return node switch
        {
            JseLiteral literal => $"lit:{SerializeValue(literal.Value)}",
            JseSymbol symbol => $"sym:{symbol.Name}",
            JseCall call => $"call:{call.Operator}({string.Join(',', call.Args.Select(SerializeNode))})",
            _ => throw new InvalidOperationException($"Unsupported AST node: {node.GetType().Name}")
        };
    }

    private static string SerializeValue(object? value)
    {
        return value switch
        {
            null => "null",
            string s => $"\"{s}\"",
            bool b => b ? "true" : "false",
            IEnumerable<object?> list => $"[{string.Join(',', list.Select(SerializeValue))}]",
            IDictionary<string, object?> dict => $"{{{string.Join(',', dict.OrderBy(k => k.Key).Select(kv => $"{kv.Key}:{SerializeValue(kv.Value)}"))}}}",
            _ => value.ToString() ?? string.Empty
        };
    }
}
