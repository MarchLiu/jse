namespace Jse.Runtime;

public sealed class RuntimeScope
{
    private readonly Dictionary<string, object?> _values = new(StringComparer.Ordinal);

    public RuntimeScope(RuntimeScope? parent = null)
    {
        Parent = parent;
    }

    public RuntimeScope? Parent { get; }

    public RuntimeScope CreateChild() => new(this);

    public void Define(string name, object? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        _values[name] = value;
    }

    public bool TryResolve(string name, out object? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);

        if (_values.TryGetValue(name, out value))
        {
            return true;
        }

        if (Parent is not null)
        {
            return Parent.TryResolve(name, out value);
        }

        value = null;
        return false;
    }
}