namespace Jse.Runtime;

public sealed class OperatorEnvironment
{
    public OperatorEnvironment(OperatorRegistry operators)
    {
        Operators = operators;
        GlobalScope = new RuntimeScope();
    }

    public OperatorRegistry Operators { get; }

    public RuntimeScope GlobalScope { get; }
}
