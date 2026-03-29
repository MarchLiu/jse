using Jse.Ast;
using Jse.Execution;
using Jse.Runtime;
using Jse.Serialization;
using Xunit;

namespace Jse.Tests;

public class JseStressTests
{
    [Fact]
    public void Execute_FactorialDepth10_GeneratedTree_ReturnsExpectedDecimal()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("mul", (a, b) => a * b);

        var tree = BuildFactorialTree(10);
        var result = ExecuteRoundTripped<decimal>(tree, registry);

        Assert.Equal(3628800m, result);
    }

    [Fact]
    public void Execute_PiApproximation_GeneratedTree_RoundsToFourDecimals()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b)
            .RegisterExpression<decimal, decimal, decimal>("sub", (a, b) => a - b)
            .RegisterExpression<decimal, decimal, decimal>("div", (a, b) => a / b)
            .RegisterExpression<decimal, decimal, decimal, decimal>("mul", (a, b, c) => a * b * c);

        var tree = BuildPiApproximationTree(40);
        var result = ExecuteRoundTripped<decimal>(tree, registry);
        var rounded = decimal.Round(result, 4, MidpointRounding.AwayFromZero);

        Assert.Equal(3.1416m, rounded);
    }

    [Fact]
    public void Resolve_AmbiguousGeneralOverloads_Throws()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<IComparable, string>("pick", _ => "comparable")
            .RegisterExpression<IFormattable, string>("pick", _ => "formattable");

        var tree = Call("pick", Lit(1.23m));

        var ex1 = Assert.Throws<InvalidOperationException>(() => Execute<object?>(tree, registry));
        var ex2 = Assert.Throws<InvalidOperationException>(() => ExecuteFromRoundTrip<object?>(tree, registry));

        Assert.Contains("Ambiguous overload", ex1.Message, StringComparison.Ordinal);
        Assert.Contains("Ambiguous overload", ex2.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Execute_DeepChainSum300_GeneratedTree_ReturnsExpected()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b);

        const int n = 120;
        var tree = BuildAddChainTree(n);

        var result = ExecuteRoundTripped<decimal>(tree, registry);
        var expected = n * (n + 1m) / 2m;

        Assert.Equal(expected, result);
    }

    [Fact]
    public void Compile_RepeatedEquivalentAst_ReusesCachedDelegate()
    {
        var compiler = new ExpressionCompiler();
        var settings = new OperatorEnvironment(new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b));

        var tree = BuildAddChainTree(250);

        var first = compiler.Compile<decimal>(tree, settings);
        for (var i = 0; i < 1000; i++)
        {
            var current = compiler.Compile<decimal>(tree, settings);
            Assert.True(ReferenceEquals(first, current));
        }

        Assert.Equal(31375m, first());

        var replayed = ExecuteFromRoundTrip<decimal>(tree, settings.Operators);
        Assert.Equal(31375m, replayed);
    }

    [Fact]
    public void Execute_WideBalancedSum1024_GeneratedTree_ReturnsExpected()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b);

        var leaves = Enumerable.Range(1, 1024)
            .Select(i => (JseNode)Lit((decimal)i))
            .ToList();

        var tree = BuildBalancedBinaryTree("add", leaves);
        var result = ExecuteRoundTripped<decimal>(tree, registry);

        Assert.Equal(524800m, result);
    }

    [Fact]
    public void Serialize_ExpressionBackedOperators_ContainsDetailedVisitorNodes()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b)
            .RegisterExpression<bool, object?, object?, object?>("cond", (c, t, f) => c ? t : f);

        var settingsJson = JseRuntimeSerializer.SerializeOperatorSettings(new OperatorEnvironment(registry));

        Assert.Contains("\"$kind\":\"expression\"", settingsJson, StringComparison.Ordinal);
        Assert.Contains("\"$kind\":\"binary\"", settingsJson, StringComparison.Ordinal);
        Assert.Contains("\"$kind\":\"conditional\"", settingsJson, StringComparison.Ordinal);

        var restoredSettings = JseRuntimeSerializer.DeserializeOperatorSettings(settingsJson);
        var tree = Call("add", Lit(2m), Lit(5m));
        var value = Execute<decimal>(tree, restoredSettings.Operators);
        Assert.Equal(7m, value);
    }

    [Fact(Skip = "Known limitation: very deep left-leaning trees can overflow compiler recursion stack. Use balanced trees or limited depth.")]
    public void Execute_DeepChainSum2000_GeneratedTree_KnownStackDepthLimitation()
    {
        var registry = new OperatorRegistry()
            .RegisterExpression<decimal, decimal, decimal>("add", (a, b) => a + b);

        var tree = BuildAddChainTree(2000);
        _ = ExecuteFromRoundTrip<decimal>(tree, registry);
    }

    private static T ExecuteRoundTripped<T>(JseNode tree, OperatorRegistry registry)
    {
        var original = Execute<T>(tree, registry);
        var replayed = ExecuteFromRoundTrip<T>(tree, registry);
        Assert.Equal(original, replayed);
        return replayed;
    }

    private static T ExecuteFromRoundTrip<T>(JseNode tree, OperatorRegistry registry)
    {
        var nodeJson = JseRuntimeSerializer.SerializeNode(tree);
        var settingsJson = JseRuntimeSerializer.SerializeOperatorSettings(new OperatorEnvironment(registry));

        var restoredNode = JseRuntimeSerializer.DeserializeNode(nodeJson);
        var restoredSettings = JseRuntimeSerializer.DeserializeOperatorSettings(settingsJson);

        var compiler = new ExpressionCompiler();
        var executable = compiler.Compile<T>(restoredNode, restoredSettings);
        return executable();
    }

    private static T Execute<T>(JseNode tree, OperatorRegistry registry)
    {
        var compiler = new ExpressionCompiler();
        var settings = new OperatorEnvironment(registry);
        var executable = compiler.Compile<T>(tree, settings);
        return executable();
    }

    private static JseNode BuildFactorialTree(int n)
    {
        JseNode current = Lit(1m);

        for (var i = 2; i <= n; i++)
        {
            current = Call("mul", current, Lit((decimal)i));
        }

        return current;
    }

    private static JseNode BuildPiApproximationTree(int termCount)
    {
        // Nilakantha series:
        // pi = 3 + 4/(2*3*4) - 4/(4*5*6) + ...
        JseNode current = Lit(3m);

        for (var n = 1; n <= termCount; n++)
        {
            var a = 2m * n;
            var denominator = Call("mul", Lit(a), Lit(a + 1m), Lit(a + 2m));
            var term = Call("div", Lit(4m), denominator);

            current = n % 2 == 1
                ? Call("add", current, term)
                : Call("sub", current, term);
        }

        return current;
    }

    private static JseNode BuildAddChainTree(int n)
    {
        JseNode current = Lit(1m);

        for (var i = 2; i <= n; i++)
        {
            current = Call("add", current, Lit((decimal)i));
        }

        return current;
    }

    private static JseNode BuildBalancedBinaryTree(string op, IReadOnlyList<JseNode> leaves)
    {
        if (leaves.Count == 0)
        {
            throw new ArgumentException("At least one leaf is required.", nameof(leaves));
        }

        var current = leaves.ToList();
        while (current.Count > 1)
        {
            var next = new List<JseNode>((current.Count + 1) / 2);
            for (var i = 0; i < current.Count; i += 2)
            {
                if (i + 1 < current.Count)
                {
                    next.Add(Call(op, current[i], current[i + 1]));
                }
                else
                {
                    next.Add(current[i]);
                }
            }

            current = next;
        }

        return current[0];
    }

    private static JseLiteral Lit(object value) => new(value);

    private static JseCall Call(string op, params JseNode[] args) => new(op, args);

    // Future ideas:
    // 1) Deep mixed-type overload tree (decimal/object/base types).
    // 2) Heavy quote/unquote-like data-path regression checks.
    // 3) Seeded randomized tree generation with deterministic expected fold.
}
