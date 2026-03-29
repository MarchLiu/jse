using System.Text.Json;
using Jse.Ast;
using Jse.Execution;
using Jse.Serialization;

namespace Jse.Runtime;

public sealed class JseEngine
{
    private readonly ExpressionCompiler _compiler;
    private readonly OperatorEnvironment _environment;

    public JseEngine()
        : this(OperatorRegistry.CreateDefault())
    {
    }

    public JseEngine(OperatorRegistry registry)
    {
        _compiler = new ExpressionCompiler();
        _environment = new OperatorEnvironment(registry);
    }

    // Convenience entry point for raw JSON text.
    public object? Execute(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return Execute(doc.RootElement);
    }

    // Preferred path when caller already has parsed JSON.
    public object? Execute(JsonElement element)
    {
        return ExecuteCore(element);
    }

    // AST entry point for already-parsed expressions.
    public object? Execute(JseNode ast)
    {
        ArgumentNullException.ThrowIfNull(ast);
        return ExecuteCore(ast);
    }

    // Single execution pipeline: parse node -> compile -> execute.
    private object? ExecuteCore(JsonElement element)
    {
        var ast = JseRuntimeSerializer.DeserializeNode(element);
        return ExecuteCore(ast);
    }

    private object? ExecuteCore(JseNode ast)
    {
        var executable = _compiler.Compile(ast, _environment);
        return executable();
    }
}
