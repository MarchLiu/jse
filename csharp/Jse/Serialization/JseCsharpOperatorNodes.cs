using System.Text.Json.Serialization;

namespace Jse.Serialization;

public sealed record JseCsharpOperatorLambdaNode(
    IReadOnlyList<JseCsharpOperatorParameterNode> Parameters,
    string ReturnType,
    JseCsharpOperatorExpressionNode Body);

public sealed record JseCsharpOperatorParameterNode(string Name, string Type);

[JsonPolymorphic(TypeDiscriminatorPropertyName = "$kind")]
[JsonDerivedType(typeof(JseCsharpOperatorParameterRefNode), typeDiscriminator: "parameter")]
[JsonDerivedType(typeof(JseCsharpOperatorConstantNode), typeDiscriminator: "constant")]
[JsonDerivedType(typeof(JseCsharpOperatorBinaryNode), typeDiscriminator: "binary")]
[JsonDerivedType(typeof(JseCsharpOperatorUnaryNode), typeDiscriminator: "unary")]
[JsonDerivedType(typeof(JseCsharpOperatorConditionalNode), typeDiscriminator: "conditional")]
[JsonDerivedType(typeof(JseCsharpOperatorMethodCallNode), typeDiscriminator: "methodCall")]
public abstract record JseCsharpOperatorExpressionNode(string Type);

public sealed record JseCsharpOperatorParameterRefNode(string Name, string Type)
    : JseCsharpOperatorExpressionNode(Type);

public sealed record JseCsharpOperatorConstantNode(string Type, string? ValueJson)
    : JseCsharpOperatorExpressionNode(Type);

public sealed record JseCsharpOperatorBinaryNode(
    string Type,
    string NodeType,
    JseCsharpOperatorExpressionNode Left,
    JseCsharpOperatorExpressionNode Right)
    : JseCsharpOperatorExpressionNode(Type);

public sealed record JseCsharpOperatorUnaryNode(
    string Type,
    string NodeType,
    JseCsharpOperatorExpressionNode Operand)
    : JseCsharpOperatorExpressionNode(Type);

public sealed record JseCsharpOperatorConditionalNode(
    string Type,
    JseCsharpOperatorExpressionNode Test,
    JseCsharpOperatorExpressionNode IfTrue,
    JseCsharpOperatorExpressionNode IfFalse)
    : JseCsharpOperatorExpressionNode(Type);

public sealed record JseCsharpOperatorMethodCallNode(
    string Type,
    string DeclaringType,
    string MethodName,
    IReadOnlyList<string> ParameterTypes,
    JseCsharpOperatorExpressionNode? Instance,
    IReadOnlyList<JseCsharpOperatorExpressionNode> Arguments)
    : JseCsharpOperatorExpressionNode(Type);
