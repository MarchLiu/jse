using System.Linq.Expressions;
using System.Threading;

namespace Jse.Runtime;

public sealed class OperatorBinding
{
    private readonly Delegate? _eagerImplementation;
    private readonly LambdaExpression? _expressionDefinition;
    private readonly Lazy<Delegate> _lazyImplementation;

    public OperatorBinding(
        string name,
        Delegate? implementation,
        IReadOnlyList<Type> parameterTypes,
        Type returnType,
        LambdaExpression? expressionDefinition = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(parameterTypes);
        ArgumentNullException.ThrowIfNull(returnType);

        if (implementation is null && expressionDefinition is null)
        {
            throw new ArgumentException("Either implementation or expressionDefinition must be provided.");
        }

        Name = name;
        _eagerImplementation = implementation;
        _expressionDefinition = expressionDefinition;
        ParameterTypes = parameterTypes;
        ReturnType = returnType;
        _lazyImplementation = new Lazy<Delegate>(
            BuildImplementation,
            LazyThreadSafetyMode.ExecutionAndPublication);
    }

    public string Name { get; }

    public Delegate Implementation => _lazyImplementation.Value;

    public IReadOnlyList<Type> ParameterTypes { get; }

    public Type ReturnType { get; }

    public LambdaExpression? ExpressionDefinition => _expressionDefinition;

    private Delegate BuildImplementation()
    {
        if (_eagerImplementation is not null)
        {
            return _eagerImplementation;
        }

        if (_expressionDefinition is null)
        {
            throw new InvalidOperationException(
                $"Operator '{Name}' has neither eager delegate nor expression definition.");
        }

        return _expressionDefinition.Compile();
    }
}
