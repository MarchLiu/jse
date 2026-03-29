using Jse.Ast;

namespace Jse.Runtime;

public interface IRuntimeCallable
{
    object? Invoke(RuntimeContext callerContext, IReadOnlyList<object?> args);
}

public sealed class RuntimeLambda : IRuntimeCallable
{
    private readonly IReadOnlyList<string> _parameterNames;
    private readonly JseNode _body;
    private readonly RuntimeScope _closure;

    public RuntimeLambda(IReadOnlyList<string> parameterNames, JseNode body, RuntimeScope closure)
    {
        _parameterNames = parameterNames;
        _body = body;
        _closure = closure;
    }

    public object? Invoke(RuntimeContext callerContext, IReadOnlyList<object?> args)
    {
        ArgumentNullException.ThrowIfNull(callerContext);
        ArgumentNullException.ThrowIfNull(args);

        if (_parameterNames.Count != args.Count)
        {
            throw new InvalidOperationException(
                $"Lambda expects {_parameterNames.Count} arguments, got {args.Count}.");
        }

        var child = _closure.CreateChild();
        for (var i = 0; i < _parameterNames.Count; i++)
        {
            child.Define(_parameterNames[i], args[i]);
        }

        var lambdaContext = new RuntimeContext(callerContext.Environment, child);
        return RuntimeEvaluator.EvaluateNode(_body, lambdaContext);
    }
}