const std = @import("std");
const JseValue = @import("../value.zig").JseValue;
const core = @import("../core.zig");
const Parser = @import("../parser.zig").Parser;

const QUERY_FIELDS = "subject, predicate, object, meta";

fn sql_pattern_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 3) return error.ArityError;

    const subj = try env.eval(args[0]);
    const pred = try env.eval(args[1]);
    const obj = try env.eval(args[2]);

    if (subj != .string or pred != .string or obj != .string) return error.TypeError;

    if (std.mem.eql(u8, subj.string, "*") and std.mem.eql(u8, pred.string, "*") and std.mem.eql(u8, obj.string, "*")) {
        return error.ValueError;
    }

    const json_str = try std.json.Stringify.valueAlloc(env.allocator, .{ .triple = .{ subj.string, pred.string, obj.string } }, .{});

    const cond = try std.fmt.allocPrint(env.allocator, "meta @> '{s}'", .{json_str});

    const sql = try std.fmt.allocPrint(env.allocator,
        \\select
        \\    subject, predicate, object, meta
        \\from statement as s
        \\where {s}
        \\offset 0
        \\limit 100
        \\
    , .{cond});

    return .{ .string = sql };
}

fn sql_and_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .string = "" };
    var parts: std.ArrayList([]const u8) = .empty;
    for (args) |arg| {
        const val = try env.eval(arg);
        if (val != .string) return error.TypeError;
        try parts.append(env.allocator, val.string);
    }
    const result = try std.mem.join(env.allocator, " and ", parts.items);
    return .{ .string = result };
}

fn sql_wildcard_fn(_: *core.Env, _: []const *core.AstNode) core.JseError!JseValue {
    return .{ .string = "*" };
}

pub fn query_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return error.ArityError;

    var local_env = core.Env.initWithParent(env.allocator, env.arena_allocator, env);
    defer local_env.deinit();

    local_env.registerFunctor("$pattern", sql_pattern_fn) catch return error.EvalError;
    local_env.registerFunctor("$and", sql_and_fn) catch return error.EvalError;
    local_env.registerFunctor("$*", sql_wildcard_fn) catch return error.EvalError;

    var parser = Parser.init(env.allocator, env.arena_allocator, &local_env);

    const condition_val = try env.eval(args[0]);
    const condition_ast = try parser.parse(condition_val);
    const where_clause = try local_env.eval(condition_ast);

    if (where_clause != .string) return error.TypeError;

    const sql = try std.fmt.allocPrint(env.allocator,
        \\select {s}
        \\from statement
        \\where
        \\    {s}
        \\
    , .{ QUERY_FIELDS, where_clause.string });

    return .{ .string = sql };
}

pub const SQL_FUNCTORS = [_]struct { []const u8, core.FunctorFn }{
    .{ "$query", query_fn },
};
