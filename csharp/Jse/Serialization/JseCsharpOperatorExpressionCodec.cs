using System.Linq.Expressions;
using System.Reflection;
using System.Text.Json;

namespace Jse.Serialization;

public static class JseCsharpOperatorExpressionCodec
{
    private static readonly JsonSerializerOptions JsonOptions = new();

    public static JseCsharpOperatorLambdaNode Serialize(LambdaExpression lambda)
    {
        ArgumentNullException.ThrowIfNull(lambda);

        var parameters = lambda.Parameters
            .Select(static p => new JseCsharpOperatorParameterNode(p.Name ?? "arg", TypeId(p.Type)))
            .ToList();

        var body = SerializeExpression(lambda.Body);
        return new JseCsharpOperatorLambdaNode(parameters, TypeId(lambda.ReturnType), body);
    }

    public static LambdaExpression Deserialize(JseCsharpOperatorLambdaNode node)
    {
        ArgumentNullException.ThrowIfNull(node);

        var parameters = node.Parameters
            .Select(static p => Expression.Parameter(ResolveType(p.Type), p.Name))
            .ToArray();

        var parameterMap = parameters.ToDictionary(static p => p.Name ?? string.Empty, static p => p, StringComparer.Ordinal);
        var body = DeserializeExpression(node.Body, parameterMap);

        var returnType = ResolveType(node.ReturnType);
        if (body.Type != returnType)
        {
            body = Expression.Convert(body, returnType);
        }

        var delegateType = Expression.GetDelegateType(parameters.Select(static p => p.Type).Append(returnType).ToArray());
        return Expression.Lambda(delegateType, body, parameters);
    }

    private static JseCsharpOperatorExpressionNode SerializeExpression(Expression expression)
    {
        return expression switch
        {
            ParameterExpression parameter => new JseCsharpOperatorParameterRefNode(parameter.Name ?? "arg", TypeId(parameter.Type)),
            ConstantExpression constant => SerializeConstant(constant),
            BinaryExpression binary => new JseCsharpOperatorBinaryNode(
                TypeId(binary.Type),
                binary.NodeType.ToString(),
                SerializeExpression(binary.Left),
                SerializeExpression(binary.Right)),
            UnaryExpression unary => new JseCsharpOperatorUnaryNode(
                TypeId(unary.Type),
                unary.NodeType.ToString(),
                SerializeExpression(unary.Operand)),
            ConditionalExpression conditional => new JseCsharpOperatorConditionalNode(
                TypeId(conditional.Type),
                SerializeExpression(conditional.Test),
                SerializeExpression(conditional.IfTrue),
                SerializeExpression(conditional.IfFalse)),
            MethodCallExpression call => new JseCsharpOperatorMethodCallNode(
                TypeId(call.Type),
                TypeId(call.Method.DeclaringType ?? throw new InvalidOperationException("Method has no declaring type.")),
                call.Method.Name,
                call.Method.GetParameters().Select(static p => TypeId(p.ParameterType)).ToList(),
                call.Object is null ? null : SerializeExpression(call.Object),
                call.Arguments.Select(SerializeExpression).ToList()),
            _ => throw new NotSupportedException($"Unsupported expression node: {expression.NodeType} ({expression.GetType().Name}).")
        };
    }

    private static JseCsharpOperatorConstantNode SerializeConstant(ConstantExpression constant)
    {
        var type = constant.Type;
        var valueJson = constant.Value is null
            ? null
            : JsonSerializer.Serialize(constant.Value, type, JsonOptions);

        return new JseCsharpOperatorConstantNode(TypeId(type), valueJson);
    }

    private static Expression DeserializeExpression(
        JseCsharpOperatorExpressionNode node,
        IReadOnlyDictionary<string, ParameterExpression> parameters)
    {
        return node switch
        {
            JseCsharpOperatorParameterRefNode parameter => DeserializeParameter(parameter, parameters),
            JseCsharpOperatorConstantNode constant => DeserializeConstant(constant),
            JseCsharpOperatorBinaryNode binary => DeserializeBinary(binary, parameters),
            JseCsharpOperatorUnaryNode unary => DeserializeUnary(unary, parameters),
            JseCsharpOperatorConditionalNode conditional => DeserializeConditional(conditional, parameters),
            JseCsharpOperatorMethodCallNode call => DeserializeMethodCall(call, parameters),
            _ => throw new NotSupportedException($"Unsupported serialized expression node type: {node.GetType().Name}.")
        };
    }

    private static Expression DeserializeParameter(
        JseCsharpOperatorParameterRefNode parameter,
        IReadOnlyDictionary<string, ParameterExpression> parameters)
    {
        if (!parameters.TryGetValue(parameter.Name, out var expression))
        {
            throw new InvalidOperationException($"Unknown parameter '{parameter.Name}'.");
        }

        return expression;
    }

    private static Expression DeserializeConstant(JseCsharpOperatorConstantNode constant)
    {
        var type = ResolveType(constant.Type);
        if (constant.ValueJson is null)
        {
            return Expression.Constant(null, type);
        }

        var value = JsonSerializer.Deserialize(constant.ValueJson, type, JsonOptions);
        return Expression.Constant(value, type);
    }

    private static Expression DeserializeBinary(
        JseCsharpOperatorBinaryNode binary,
        IReadOnlyDictionary<string, ParameterExpression> parameters)
    {
        var left = DeserializeExpression(binary.Left, parameters);
        var right = DeserializeExpression(binary.Right, parameters);

        return ParseNodeType(binary.NodeType) switch
        {
            ExpressionType.Add => Expression.Add(left, right),
            ExpressionType.Subtract => Expression.Subtract(left, right),
            ExpressionType.Multiply => Expression.Multiply(left, right),
            ExpressionType.Divide => Expression.Divide(left, right),
            ExpressionType.Equal => Expression.Equal(left, right),
            ExpressionType.AndAlso => Expression.AndAlso(left, right),
            ExpressionType.OrElse => Expression.OrElse(left, right),
            ExpressionType.LessThan => Expression.LessThan(left, right),
            ExpressionType.LessThanOrEqual => Expression.LessThanOrEqual(left, right),
            ExpressionType.GreaterThan => Expression.GreaterThan(left, right),
            ExpressionType.GreaterThanOrEqual => Expression.GreaterThanOrEqual(left, right),
            _ => throw new NotSupportedException($"Unsupported binary node type: {binary.NodeType}.")
        };
    }

    private static Expression DeserializeUnary(
        JseCsharpOperatorUnaryNode unary,
        IReadOnlyDictionary<string, ParameterExpression> parameters)
    {
        var operand = DeserializeExpression(unary.Operand, parameters);
        var targetType = ResolveType(unary.Type);

        return ParseNodeType(unary.NodeType) switch
        {
            ExpressionType.Convert => Expression.Convert(operand, targetType),
            ExpressionType.Not => Expression.Not(operand),
            ExpressionType.Negate => Expression.Negate(operand),
            _ => throw new NotSupportedException($"Unsupported unary node type: {unary.NodeType}.")
        };
    }

    private static Expression DeserializeConditional(
        JseCsharpOperatorConditionalNode conditional,
        IReadOnlyDictionary<string, ParameterExpression> parameters)
    {
        var test = DeserializeExpression(conditional.Test, parameters);
        var ifTrue = DeserializeExpression(conditional.IfTrue, parameters);
        var ifFalse = DeserializeExpression(conditional.IfFalse, parameters);
        return Expression.Condition(test, ifTrue, ifFalse);
    }

    private static Expression DeserializeMethodCall(
        JseCsharpOperatorMethodCallNode call,
        IReadOnlyDictionary<string, ParameterExpression> parameters)
    {
        var declaringType = ResolveType(call.DeclaringType);
        var methodParameterTypes = call.ParameterTypes.Select(ResolveType).ToArray();

        var method = declaringType.GetMethod(
            call.MethodName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static,
            binder: null,
            types: methodParameterTypes,
            modifiers: null)
            ?? throw new InvalidOperationException(
                $"Method '{call.MethodName}' not found on '{declaringType.FullName}'.");

        var instance = call.Instance is null
            ? null
            : DeserializeExpression(call.Instance, parameters);

        var args = call.Arguments.Select(arg => DeserializeExpression(arg, parameters)).ToArray();
        return Expression.Call(instance, method, args);
    }

    private static ExpressionType ParseNodeType(string nodeType)
    {
        if (!Enum.TryParse<ExpressionType>(nodeType, out var value))
        {
            throw new InvalidOperationException($"Unknown ExpressionType '{nodeType}'.");
        }

        return value;
    }

    private static string TypeId(Type type) =>
        type.AssemblyQualifiedName
        ?? throw new InvalidOperationException($"Type '{type.FullName}' has no assembly-qualified name.");

    private static Type ResolveType(string typeId) =>
        Type.GetType(typeId, throwOnError: false)
        ?? throw new InvalidOperationException($"Unable to resolve type '{typeId}'.");
}
