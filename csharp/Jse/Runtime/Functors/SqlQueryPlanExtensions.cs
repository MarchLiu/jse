using System.Data;
using System.Data.SqlClient;
using System.Text.Json.Nodes;

namespace Jse.Runtime.Functors;

public static class SqlQueryPlanExtensions
{
    public static SqlCommand ToSqlCommand(this SqlQueryPlan plan, SqlConnection connection)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(connection);

        var command = connection.CreateCommand();
        command.CommandType = CommandType.Text;
        command.CommandText = plan.SqlText;

        foreach (var parameter in plan.Parameters)
        {
            var sqlParameter = new SqlParameter($"@{parameter.Name}", parameter.DbType)
            {
                Value = ResolveParameterValue(parameter)
            };
            command.Parameters.Add(sqlParameter);
        }

        return command;
    }

    public static int ExecuteNonQuery(this SqlQueryPlan plan, SqlConnection connection)
    {
        using var command = plan.ToSqlCommand(connection);
        EnsureOpen(connection);
        return command.ExecuteNonQuery();
    }

    public static object? ExecuteScalar(this SqlQueryPlan plan, SqlConnection connection)
    {
        using var command = plan.ToSqlCommand(connection);
        EnsureOpen(connection);
        return command.ExecuteScalar();
    }

    private static object ResolveParameterValue(SqlQueryParameter parameter)
    {
        var scalar = TryGetScalar(parameter.ParsedValue);
        return scalar ?? parameter.JsonText;
    }

    private static object? TryGetScalar(JsonNode? node)
    {
        if (node is not JsonValue value)
        {
            return null;
        }

        if (value.TryGetValue<bool>(out var boolean))
        {
            return boolean;
        }

        if (value.TryGetValue<int>(out var intValue))
        {
            return intValue;
        }

        if (value.TryGetValue<long>(out var longValue))
        {
            return longValue;
        }

        if (value.TryGetValue<decimal>(out var decimalValue))
        {
            return decimalValue;
        }

        if (value.TryGetValue<double>(out var doubleValue))
        {
            return doubleValue;
        }

        if (value.TryGetValue<string>(out var stringValue))
        {
            return stringValue;
        }

        return null;
    }

    private static void EnsureOpen(SqlConnection connection)
    {
        if (connection.State != ConnectionState.Open)
        {
            connection.Open();
        }
    }
}