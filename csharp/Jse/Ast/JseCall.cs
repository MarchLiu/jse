using System.Collections.ObjectModel;

namespace Jse.Ast;

public sealed record JseCall(
    string Operator,
    IReadOnlyList<JseNode> Args,
    IReadOnlyDictionary<string, object?>? Meta = null) : JseNode
{
    public IReadOnlyList<JseNode> Args { get; } = new ReadOnlyCollection<JseNode>(Args.ToList());
    public IReadOnlyDictionary<string, object?>? Meta { get; } = Meta is null
        ? null
        : new ReadOnlyDictionary<string, object?>(new Dictionary<string, object?>(Meta));
}
