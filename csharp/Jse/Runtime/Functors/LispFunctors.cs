using Jse.Ast;

namespace Jse.Runtime.Functors;

public static class LispFunctors
{
    public static object? Cond(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        if (args.Count == 0)
        {
            return null;
        }

        var hasDefault = args.Count % 2 == 1;
        var pairCount = hasDefault ? args.Count - 1 : args.Count;

        for (var i = 0; i < pairCount; i += 2)
        {
            var testValue = RuntimeEvaluator.EvaluateNode(args[i], context);
            if (IsTruthy(testValue))
            {
                return RuntimeEvaluator.EvaluateNode(args[i + 1], context);
            }
        }

        if (hasDefault)
        {
            return RuntimeEvaluator.EvaluateNode(args[^1], context);
        }

        return null;
    }

    public static object? Quote(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        EnsureMinArgs("$quote", args, 1);

        if (args.Count == 1)
        {
            return RuntimeEvaluator.QuoteNode(args[0]);
        }

        return args.Select(RuntimeEvaluator.QuoteNode).ToList();
    }

    public static object? Eval(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        EnsureMinArgs("$eval", args, 1);
        var expressionValue = RuntimeEvaluator.EvaluateNode(args[0], context);
        var expression = RuntimeEvaluator.ParseRuntimeExpression(expressionValue);
        return RuntimeEvaluator.EvaluateNode(expression, context);
    }

    public static object? Apply(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        EnsureMinArgs("$apply", args, 2);

        var functor = args[0] is JseSymbol symbol
            ? $"${symbol.Name}"
            : RuntimeEvaluator.EvaluateNode(args[0], context);
        var argListValue = RuntimeEvaluator.EvaluateNode(args[1], context);

        if (argListValue is not List<object?> list)
        {
            throw new InvalidOperationException("$apply second argument must be a list.");
        }

        return RuntimeEvaluator.InvokeByValue(context, functor, list);
    }

    public static RuntimeLambda Lambda(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        EnsureMinArgs("$lambda", args, 2);

        var paramsValue = RuntimeEvaluator.EvaluateNode(args[0], context);
        var paramNames = ExtractParamNames(paramsValue);
        var body = args[1];

        return new RuntimeLambda(paramNames, body, context.Scope);
    }

    public static object? Def(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        EnsureMinArgs("$def", args, 2);

        var name = ExtractName(args[0], context);
        var value = RuntimeEvaluator.EvaluateNode(args[1], context);

        context.Scope.Define(name, value);
        return value;
    }

    public static RuntimeLambda Defn(RuntimeContext context, IReadOnlyList<JseNode> args)
    {
        EnsureMinArgs("$defn", args, 3);

        var name = ExtractName(args[0], context);
        var lambda = Lambda(context, new[] { args[1], args[2] });
        context.Scope.Define(name, lambda);
        return lambda;
    }

    private static List<string> ExtractParamNames(object? value)
    {
        if (value is not List<object?> list)
        {
            throw new InvalidOperationException("$lambda first argument must evaluate to a list of symbols.");
        }

        var names = new List<string>(list.Count);
        foreach (var item in list)
        {
            if (item is not string s || !s.StartsWith('$'))
            {
                throw new InvalidOperationException("$lambda parameters must be symbol strings like '$x'.");
            }

            names.Add(RuntimeEvaluator.NormalizeName(s));
        }

        return names;
    }

    private static string ExtractName(JseNode nameNode, RuntimeContext context)
    {
        if (nameNode is JseSymbol symbol)
        {
            return symbol.Name;
        }

        var value = RuntimeEvaluator.EvaluateNode(nameNode, context);
        if (value is string s && s.StartsWith('$'))
        {
            return RuntimeEvaluator.NormalizeName(s);
        }

        throw new InvalidOperationException("First argument must be a symbol.");
    }

    private static void EnsureMinArgs(string name, IReadOnlyList<JseNode> args, int count)
    {
        if (args.Count < count)
        {
            throw new InvalidOperationException($"{name} requires at least {count} arguments.");
        }
    }

    private static bool IsTruthy(object? value)
    {
        return value switch
        {
            null => false,
            bool b => b,
            _ => true
        };
    }
}