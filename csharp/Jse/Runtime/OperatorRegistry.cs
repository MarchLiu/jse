using System.Collections.ObjectModel;
using System.Linq.Expressions;
using Jse.Ast;
using Jse.Runtime.Functors;

namespace Jse.Runtime;

public sealed class OperatorRegistry
{
    private readonly Dictionary<string, List<OperatorBinding>> _operators = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Func<RuntimeContext, IReadOnlyList<JseNode>, object?>> _specialOperators =
        new(StringComparer.Ordinal);
    private readonly Dictionary<string, Func<IReadOnlyList<object?>, object?>> _variadicOperators =
        new(StringComparer.Ordinal);

    public OperatorRegistry RegisterExpression<TResult>(string name, Expression<Func<TResult>> definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        return RegisterExpression(name, (LambdaExpression)definition);
    }


    public OperatorRegistry RegisterExpression<T1, TResult>(string name, Expression<Func<T1, TResult>> definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        return RegisterExpression(name, (LambdaExpression)definition);
    }


    public OperatorRegistry RegisterExpression<T1, T2, TResult>(string name, Expression<Func<T1, T2, TResult>> definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        return RegisterExpression(name, (LambdaExpression)definition);
    }


    public OperatorRegistry RegisterExpression<T1, T2, T3, TResult>(string name, Expression<Func<T1, T2, T3, TResult>> definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        return RegisterExpression(name, (LambdaExpression)definition);
    }

    public OperatorRegistry RegisterExpression(string name, LambdaExpression definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        var parameterTypes = definition.Parameters.Select(static p => p.Type).ToArray();
        return RegisterBinding(name, parameterTypes, definition.ReturnType, definition);
    }


    public OperatorRegistry RegisterSpecialExpression(
        string name,
        Expression<Func<RuntimeContext, IReadOnlyList<JseNode>, object?>> definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        _specialOperators[name] = definition.Compile();
        return this;
    }


    public OperatorRegistry RegisterVariadicExpression<TResult>(
        string name,
        Expression<Func<IReadOnlyList<object?>, TResult>> definition)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(definition);

        var compiled = definition.Compile();
        _variadicOperators[name] = args => compiled(args);
        return this;
    }

    private OperatorRegistry RegisterBinding(
        string name,    
        IReadOnlyList<Type> parameterTypes,
        Type returnType,
        LambdaExpression? expressionDefinition )
    {
        if (!_operators.TryGetValue(name, out var overloads))
        {
            overloads = new List<OperatorBinding>();
            _operators[name] = overloads;
        }

        overloads.Add(new OperatorBinding(name, null, parameterTypes, returnType, expressionDefinition));
        return this;
    }

    public OperatorBinding Resolve(string name, IReadOnlyList<Type> argumentTypes)
    {
        if (!_operators.TryGetValue(name, out var overloads))
        {
            throw new InvalidOperationException($"Operator '{name}' is not registered.");
        }

        var candidates = overloads
            .Where(binding => IsApplicable(binding, argumentTypes))
            .ToList();

        if (candidates.Count == 0)
        {
            throw new InvalidOperationException(
                $"No applicable overload found for operator '{name}' with argument types ({string.Join(", ", argumentTypes.Select(static t => t.Name))}).");
        }

        candidates.Sort((x, y) => CompareSpecificity(x, y, argumentTypes));

        if (candidates.Count > 1 && CompareSpecificity(candidates[0], candidates[1], argumentTypes) == 0)
        {
            throw new InvalidOperationException(
                $"Ambiguous overload for operator '{name}' with argument types ({string.Join(", ", argumentTypes.Select(static t => t.Name))}).");
        }

        return candidates[0];
    }

    public IReadOnlyDictionary<string, IReadOnlyList<OperatorBinding>> Snapshot() =>
        new ReadOnlyDictionary<string, IReadOnlyList<OperatorBinding>>(
            _operators.ToDictionary(static kvp => kvp.Key, static kvp => (IReadOnlyList<OperatorBinding>)kvp.Value.AsReadOnly()));

    public bool TryResolveSpecial(string name, out Func<RuntimeContext, IReadOnlyList<JseNode>, object?> implementation)
    {
        return _specialOperators.TryGetValue(name, out implementation!);
    }

    public bool TryResolveVariadic(string name, out Func<IReadOnlyList<object?>, object?> implementation)
    {
        return _variadicOperators.TryGetValue(name, out implementation!);
    }

    public static OperatorRegistry CreateDefault()
    {
        var registry = new OperatorRegistry();

        registry.RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b);
        registry.RegisterExpression<long, long, long>("add", (a, b) => a + b);
        registry.RegisterExpression<double, double, double>("add", (a, b) => a + b);
        registry.RegisterExpression<object?, object?, bool>("eq", (left, right) => DefaultFunctors.Eq(left, right));
        registry.RegisterExpression<object?, bool>("eq", value => DefaultFunctors.Eq1(value));
        registry.RegisterExpression<object?, object?, object?, bool>("eq", (a, b, c) => DefaultFunctors.Eq3(a, b, c));
        registry.RegisterVariadicExpression<bool>("eq", args => DefaultFunctors.EqVariadic(args));

        registry.RegisterExpression<bool, bool, bool>("and", (left, right) => left && right);
        registry.RegisterExpression<bool, bool, bool, bool>("and", (a, b, c) => a && b && c);
        registry.RegisterVariadicExpression<bool>("and", args => DefaultFunctors.AndVariadic(args));
        registry.RegisterExpression<bool, bool, bool>("or", (left, right) => left || right);
        registry.RegisterExpression<bool, bool, bool, bool>("or", (a, b, c) => a || b || c);
        registry.RegisterVariadicExpression<bool>("or", args => DefaultFunctors.OrVariadic(args));
        registry.RegisterExpression<bool, object?, object?, object?>("cond", (c, t, f) => c ? t : f);

        registry.RegisterExpression<List<object?>, object?>("head", list => DefaultFunctors.Head(list));
        registry.RegisterExpression<List<object?>, List<object?>>("tail", list => DefaultFunctors.Tail(list));
        registry.RegisterExpression<object?, bool>("atom?", value => DefaultFunctors.Atom(value));
        registry.RegisterExpression<object?, List<object?>, List<object?>>("cons", (value, list) => DefaultFunctors.Cons(value, list));

        registry.RegisterExpression<object?, bool>("not", value => DefaultFunctors.Not(value));
        registry.RegisterExpression<object?, bool>("list?", value => DefaultFunctors.ListP(value));
        registry.RegisterExpression<object?, bool>("map?", value => DefaultFunctors.MapP(value));
        registry.RegisterExpression<object?, bool>("null?", value => DefaultFunctors.NullP(value));
        registry.RegisterExpression<bool>("null?", () => DefaultFunctors.NullP0());

        registry.RegisterExpression<Dictionary<string, object?>, string, object?>("get", (map, key) => DefaultFunctors.Get(map, key));
        registry.RegisterExpression<List<object?>, decimal, object?>("get", (list, index) => DefaultFunctors.Get(list, index));
        registry.RegisterExpression<Dictionary<string, object?>, string, object?, Dictionary<string, object?>>("set", (map, key, value) => DefaultFunctors.Set(map, key, value));
        registry.RegisterExpression<List<object?>, decimal, object?, List<object?>>("set", (list, index, value) => DefaultFunctors.Set(list, index, value));
        registry.RegisterExpression<Dictionary<string, object?>, string, Dictionary<string, object?>>("del", (map, key) => DefaultFunctors.Del(map, key));
        registry.RegisterExpression<List<object?>, decimal, List<object?>>("del", (list, index) => DefaultFunctors.Del(list, index));
        registry.RegisterExpression<object?, List<object?>, List<object?>>("conj", (value, list) => DefaultFunctors.Conj(value, list));

        registry.RegisterSpecialExpression("quote", (context, args) => LispFunctors.Quote(context, args));
        registry.RegisterSpecialExpression("cond", (context, args) => LispFunctors.Cond(context, args));
        registry.RegisterSpecialExpression("eval", (context, args) => LispFunctors.Eval(context, args));
        registry.RegisterSpecialExpression("apply", (context, args) => LispFunctors.Apply(context, args));
        registry.RegisterSpecialExpression("lambda", (context, args) => (object?)LispFunctors.Lambda(context, args));
        registry.RegisterSpecialExpression("def", (context, args) => LispFunctors.Def(context, args));
        registry.RegisterSpecialExpression("defn", (context, args) => (object?)LispFunctors.Defn(context, args));
        registry.RegisterSpecialExpression("query", (context, args) => (object?)SqlFunctors.Query(context, args));  //need configure default sql connection ? 

        return registry;
    }

    private static bool IsApplicable(OperatorBinding binding, IReadOnlyList<Type> argumentTypes)
    {
        if (binding.ParameterTypes.Count != argumentTypes.Count)
        {
            return false;
        }

        for (var i = 0; i < argumentTypes.Count; i++)
        {
            var parameterType = binding.ParameterTypes[i];
            var argumentType = argumentTypes[i];

            if (!CanAssign(argumentType, parameterType))
            {
                return false;
            }
        }

        return true;
    }

    private static int CompareSpecificity(OperatorBinding x, OperatorBinding y, IReadOnlyList<Type> argumentTypes)
    {
        var xBetter = 0;
        var yBetter = 0;

        for (var i = 0; i < argumentTypes.Count; i++)
        {
            var xDistance = TypeDistance(argumentTypes[i], x.ParameterTypes[i]);
            var yDistance = TypeDistance(argumentTypes[i], y.ParameterTypes[i]);

            if (xDistance < yDistance)
            {
                xBetter++;
            }
            else if (yDistance < xDistance)
            {
                yBetter++;
            }
        }

        if (xBetter > 0 && yBetter == 0)
        {
            return -1;
        }

        if (yBetter > 0 && xBetter == 0)
        {
            return 1;
        }

        return 0;
    }

    private static bool CanAssign(Type sourceType, Type targetType)
    {
        if (sourceType == targetType)
        {
            return true;
        }

        if (sourceType == typeof(object))
        {
            return !targetType.IsValueType || Nullable.GetUnderlyingType(targetType) is not null;
        }

        return targetType.IsAssignableFrom(sourceType);
    }

    private static int TypeDistance(Type sourceType, Type targetType)
    {
        if (sourceType == targetType)
        {
            return 0;
        }

        if (targetType == typeof(object))
        {
            return 100;
        }

        if (sourceType == typeof(object))
        {
            return 90;
        }

        if (targetType.IsInterface)
        {
            return 50;
        }

        if (targetType.IsAssignableFrom(sourceType))
        {
            var distance = 1;
            var current = sourceType.BaseType;
            while (current is not null && current != targetType)
            {
                distance++;
                current = current.BaseType;
            }

            return distance;
        }

        return int.MaxValue;
    }
}
