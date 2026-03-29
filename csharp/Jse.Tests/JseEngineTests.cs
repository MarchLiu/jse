using System.Text.Json;
using System.Data;
using System.Data.SqlClient;
using Jse.Runtime;
using Jse.Runtime.Functors;
using Xunit;

namespace Jse.Tests;

public class JseEngineTests
{
    private readonly JseEngine _engine = new();

    [Theory]
    [InlineData("42", 42L)]
    [InlineData("\"hello\"", "hello")]
    [InlineData("true", true)]
    public void Execute_LiteralValues_ReturnsOriginal(string json, object expected)
    {
        var result = _engine.Execute(json);

        if (expected is long && result is not null)
        {
            Assert.Equal(Convert.ToInt64(expected), Convert.ToInt64(result));
            return;
        }

        Assert.Equal(expected, result);
    }

    [Fact]
    public void Execute_SimpleExpression_Addition()
    {
        var result = _engine.Execute("[\"$add\",1,2]");
        Assert.Equal(3.JsonValue(), result);
    }

    [Fact]
    public void Execute_NestedExpression_Addition()
    {
        var result = _engine.Execute("[\"$add\",1,[\"$add\",2,3]]");
        Assert.Equal(6.JsonValue(), result);
    }

    [Fact]
    public void Execute_NamedForm_Addition()
    {
        var json = """
                   {
                     "$add": [1, 2],
                     "source": "user"
                   }
                   """;

        var result = _engine.Execute(json);
        Assert.Equal(3.JsonValue(), result);
    }

    [Fact]
    public void Execute_Quote_PreventsEvaluation()
    {
        var result = _engine.Execute("[\"$quote\",[\"$add\",1,2]]");
        var quoted = Assert.IsType<List<object?>>(result);

        Assert.Equal("$add", quoted[0]);
        Assert.Equal(1.JsonValue(), quoted[1]);
        Assert.Equal(2.JsonValue(), quoted[2]);
    }

    [Fact]
    public void Execute_Quote_ObjectExpression_PreservesMetadataShape()
    {
        var result = _engine.Execute("[\"$quote\",{\"$add\":[1,2],\"source\":\"user\"}]");

        var quoted = Assert.IsType<Dictionary<string, object?>>(result);
        Assert.Equal("user", quoted["source"]);

        var addArgs = Assert.IsType<List<object?>>(quoted["$add"]);
        Assert.Equal(1.JsonValue(), addArgs[0]);
        Assert.Equal(2.JsonValue(), addArgs[1]);
    }

    [Fact]
    public void Execute_SymbolEscape_ReturnsLiteralDollarString()
    {
        var result = _engine.Execute("\"$$add\"");
        Assert.Equal("$add", result);
    }

    [Fact]
    public void Execute_UnresolvedSymbol_ThrowsSymbolNotFound()
    {
        var ex = Assert.Throws<KeyNotFoundException>(() => _engine.Execute("\"$missing\""));
        Assert.Contains("SymbolNotFound", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Execute_WildcardString_IsLiteralNotSymbol()
    {
        var result = _engine.Execute("\"$*\"");
        Assert.Equal("$*", result);
    }

    [Fact]
    public void Execute_ObjectWithMultipleSymbolKeys_ThrowsStructureError()
    {
        var ex = Assert.Throws<InvalidOperationException>(() => _engine.Execute("{\"$add\":[1,2],\"$eq\":[1,1]}"));
        Assert.Contains("JSE_STRUCTURE_ERROR", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Execute_WithJsonElementInput_Works()
    {
        using var doc = JsonDocument.Parse("[\"$eq\", 1, 1]");
        var result = _engine.Execute(doc.RootElement);
        Assert.Equal(true, result);
    }

    [Fact]
    public void Execute_ListBuiltinFunctors_WorkAsExpected()
    {
        var head = _engine.Execute("[\"$head\", [1,2,3]]");
        Assert.Equal(1.JsonValue(), head);

        var tail = _engine.Execute("[\"$tail\", [1,2,3]]");
        var tailList = Assert.IsType<List<object?>>(tail);
        Assert.Equal(2.JsonValue(), tailList[0]);
        Assert.Equal(3.JsonValue(), tailList[1]);

        var cons = _engine.Execute("[\"$cons\", 0, [1,2]]");
        var consList = Assert.IsType<List<object?>>(cons);
        Assert.Equal(0.JsonValue(), consList[0]);
        Assert.Equal(1.JsonValue(), consList[1]);
        Assert.Equal(2.JsonValue(), consList[2]);
    }

    [Fact]
    public void Execute_TypePredicateFunctors_WorkAsExpected()
    {
        Assert.Equal(true, _engine.Execute("[\"$atom?\", \"s\"]"));
        Assert.Equal(false, _engine.Execute("[\"$atom?\", [1]]"));
        Assert.Equal(true, _engine.Execute("[\"$list?\", [1,2]]"));
        Assert.Equal(true, _engine.Execute("[\"$map?\", {\"x\": 1}]"));
        Assert.Equal(true, _engine.Execute("[\"$null?\"]"));
        Assert.Equal(true, _engine.Execute("[\"$null?\", null]"));
        Assert.Equal(false, _engine.Execute("[\"$null?\", false]"));
    }

    [Fact]
    public void Execute_CollectionOps_WorkAsExpected()
    {
        var getMap = _engine.Execute("[\"$get\", {\"a\": 7}, \"a\"]");
        Assert.Equal(7.JsonValue(), getMap);

        var getList = _engine.Execute("[\"$get\", [10,11,12], 1]");
        Assert.Equal(11.JsonValue(), getList);

        var setMap = _engine.Execute("[\"$set\", {\"a\": 1}, \"a\", 8]");
        var map = Assert.IsType<Dictionary<string, object?>>(setMap);
        Assert.Equal(8.JsonValue(), map["a"]);

        var setList = _engine.Execute("[\"$set\", [1,2,3], 1, 9]");
        var setListValue = Assert.IsType<List<object?>>(setList);
        Assert.Equal(9.JsonValue(), setListValue[1]);

        var delMap = _engine.Execute("[\"$del\", {\"a\": 1, \"b\": 2}, \"a\"]");
        var delMapValue = Assert.IsType<Dictionary<string, object?>>(delMap);
        Assert.False(delMapValue.ContainsKey("a"));

        var delList = _engine.Execute("[\"$del\", [1,2,3], 1]");
        var delListValue = Assert.IsType<List<object?>>(delList);
        Assert.Equal(2, delListValue.Count);
        Assert.Equal(1.JsonValue(), delListValue[0]);
        Assert.Equal(3.JsonValue(), delListValue[1]);
    }

    [Fact]
    public void Execute_LogicAndEqFunctors_WorkAsExpected()
    {
        Assert.Equal(true, _engine.Execute("[\"$eq\", 1]"));
        Assert.Equal(true, _engine.Execute("[\"$eq\", 1, 1, 1]"));
        Assert.Equal(false, _engine.Execute("[\"$eq\", 1, 2, 1]"));

        Assert.Equal(false, _engine.Execute("[\"$not\", true]"));
        Assert.Equal(true, _engine.Execute("[\"$and\", true, true, true]"));
        Assert.Equal(false, _engine.Execute("[\"$and\", true, false, true]"));
        Assert.Equal(true, _engine.Execute("[\"$or\", false, false, true]"));
        Assert.Equal(false, _engine.Execute("[\"$or\", false, false, false]"));

        var conj = _engine.Execute("[\"$conj\", 3, [1,2]]");
        var conjList = Assert.IsType<List<object?>>(conj);
        Assert.Equal(1.JsonValue(), conjList[0]);
        Assert.Equal(2.JsonValue(), conjList[1]);
        Assert.Equal(3.JsonValue(), conjList[2]);
    }

    [Fact]
    public void Execute_Def_StoresSymbolInGlobalScope()
    {
        var defined = _engine.Execute("[\"$def\", \"$x\", 41]");
        Assert.Equal(41.JsonValue(), defined);

        var resolved = _engine.Execute("[\"$add\", \"$x\", 1]");
        Assert.Equal(42.JsonValue(), resolved);
    }

    [Fact]
    public void Execute_DefnAndLambda_InvokeWithLexicalBinding()
    {
        _engine.Execute("[\"$defn\", \"$inc\", [\"$quote\", [\"$x\"]], [\"$add\", \"$x\", 1]]");

        var result = _engine.Execute("[\"$inc\", 7]");
        Assert.Equal(8.JsonValue(), result);
    }

    [Fact]
    public void Execute_ApplyAndEval_WorkAsExpected()
    {
        var applied = _engine.Execute("[\"$apply\", \"$add\", [5,6]]");
        Assert.Equal(11.JsonValue(), applied);

        var variadicEqApplied = _engine.Execute("[\"$apply\", \"$eq\", [1,1,1,1]]");
        Assert.Equal(true, variadicEqApplied);

        var evaluated = _engine.Execute("[\"$eval\", [\"$quote\", [\"$add\", 1, 2]]]");
        Assert.Equal(3.JsonValue(), evaluated);
    }

    [Fact]
    public void Execute_VariadicEqAndOr_WorkAsExpected()
    {
        Assert.Equal(true, _engine.Execute("[\"$eq\", 1, 1, 1, 1]"));
        Assert.Equal(false, _engine.Execute("[\"$eq\", 1, 1, 2, 1]"));

        Assert.Equal(true, _engine.Execute("[\"$and\", true, 1, \"x\"]"));
        Assert.Equal(false, _engine.Execute("[\"$and\", true, null, \"x\"]"));

        Assert.Equal(true, _engine.Execute("[\"$or\", false, null, \"x\"]"));
        Assert.Equal(false, _engine.Execute("[\"$or\", false, null, false]"));
    }

    [Fact]
    public void Execute_Cond_MultiBranchAndLazyEvaluation_WorkAsExpected()
    {
        var branch = _engine.Execute("[\"$cond\", false, [\"$unknown\"], true, 7, 9]");
        Assert.Equal(7.JsonValue(), branch);

        var fallback = _engine.Execute("[\"$cond\", false, 1, false, 2, 42]");
        Assert.Equal(42.JsonValue(), fallback);
    }

        [Fact]
        public void Execute_Query_BuildsSqlFromSinglePattern()
        {
                var query = """
                                        {
                                            "$query": { "$quote": ["$pattern", "$*", "author of", "$*"] }
                                        }
                                        """;

                var result = Assert.IsType<SqlQueryPlan>(_engine.Execute(query));

                Assert.Contains("select", result.SqlText, StringComparison.OrdinalIgnoreCase);
                Assert.Contains(SqlFunctors.QueryFields, result.SqlText, StringComparison.Ordinal);
                Assert.Contains("from statement", result.SqlText, StringComparison.Ordinal);
                Assert.Contains("meta @> CAST(@p0 AS jsonb)", result.SqlText, StringComparison.Ordinal);
                Assert.Contains("offset 0", result.SqlText, StringComparison.Ordinal);
                Assert.Contains("limit 100", result.SqlText, StringComparison.Ordinal);
                var payload = Assert.Single(result.Parameters);
                Assert.Equal("p0", payload.Name);
                Assert.Equal(SqlDbType.NVarChar, payload.DbType);
                Assert.Contains("author of", payload.JsonText, StringComparison.Ordinal);
                Assert.Contains("triple", payload.JsonText, StringComparison.Ordinal);
                Assert.NotNull(payload.ParsedValue["triple"]);
        }

        [Fact]
        public void Execute_Query_BuildsSqlFromAndPatterns()
        {
                var query = """
                                        {
                                            "$query": {
                                                "$quote": [
                                                    "$and",
                                                    ["$pattern", "Liu Xin", "author of", "$*"],
                                                    ["$pattern", "$*", "author of", "$*"]
                                                ]
                                            }
                                        }
                                        """;

                var result = Assert.IsType<SqlQueryPlan>(_engine.Execute(query));

                Assert.Contains($"select {SqlFunctors.QueryFields}", result.SqlText, StringComparison.Ordinal);
                Assert.Contains("from statement", result.SqlText, StringComparison.Ordinal);
                Assert.Contains(" and ", result.SqlText, StringComparison.Ordinal);
                Assert.Contains("offset 0", result.SqlText, StringComparison.Ordinal);
                Assert.Contains("limit 100", result.SqlText, StringComparison.Ordinal);

                Assert.Equal(2, result.Parameters.Count);
                var p0 = result.Parameters[0];
                var p1 = result.Parameters[1];
                Assert.Equal(SqlDbType.NVarChar, p0.DbType);
                Assert.Equal(SqlDbType.NVarChar, p1.DbType);
                Assert.Contains("Liu Xin", p0.JsonText, StringComparison.Ordinal);
                Assert.Contains("author of", p0.JsonText, StringComparison.Ordinal);
                Assert.Contains("author of", p1.JsonText, StringComparison.Ordinal);
        }

            [Fact]
            public void SqlQueryPlan_ToSqlCommand_BindsParametersBySqlDbType()
            {
                var plan = new SqlQueryPlan(
                    "select 1 where @p0 is not null",
                    new[]
                    {
                        new SqlQueryParameter(
                            "p0",
                            SqlDbType.NVarChar,
                            "{\"triple\":[\"author of\"]}",
                            System.Text.Json.Nodes.JsonNode.Parse("{\"triple\":[\"author of\"]}")!)
                    });

                using var connection = new SqlConnection();
                using var command = plan.ToSqlCommand(connection);

                Assert.Equal(plan.SqlText, command.CommandText);
                Assert.Single(command.Parameters);

                var parameter = Assert.IsType<SqlParameter>(command.Parameters[0]);
                Assert.Equal("@p0", parameter.ParameterName);
                Assert.Equal(SqlDbType.NVarChar, parameter.SqlDbType);
                Assert.Equal("{\"triple\":[\"author of\"]}", parameter.Value);
            }
}
