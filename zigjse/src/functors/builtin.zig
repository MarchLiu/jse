const std = @import("std");
const JseValue = @import("../value.zig").JseValue;
const core = @import("../core.zig");

/// $quote: return argument without evaluation
pub fn quote_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .null;
    const node = args[0];
    return nodeToValue(env, node);
}

/// Convert an AST node back to a JseValue (for quote)
fn nodeToValue(env: *core.Env, node: *core.AstNode) core.JseError!JseValue {
    return switch (node.*) {
        .literal => |lit| try lit.value.deepClone(env.allocator),
        .symbol => |sym| .{ .string = try env.allocator.dupe(u8, sym.name) },
        .array_node => |arr| {
            var result: std.ArrayList(JseValue) = .empty;
            try result.ensureTotalCapacity(env.allocator, arr.elements.items.len);
            for (arr.elements.items) |elem| {
                result.appendAssumeCapacity(try nodeToValue(env, elem));
            }
            return .{ .array = result };
        },
        .object_node => |obj| {
            var result = std.StringHashMap(JseValue).init(env.allocator);
            for (obj.pairs.items) |pair| {
                const key_copy = try env.allocator.dupe(u8, pair.key);
                const val = try nodeToValue(env, pair.value);
                try result.put(key_copy, val);
            }
            return .{ .object = result };
        },
        .expression => |expr| {
            var result = std.StringHashMap(JseValue).init(env.allocator);
            const key = try env.allocator.dupe(u8, expr.operator);
            const val = try nodeToValue(env, expr.value);
            try result.put(key, val);
            var it = expr.metadata.iterator();
            while (it.next()) |entry| {
                const meta_key = try env.allocator.dupe(u8, entry.key_ptr.*);
                const meta_val = try nodeToValue(env, entry.value_ptr.*);
                try result.put(meta_key, meta_val);
            }
            return .{ .object = result };
        },
        .quote => |q| q.value.deepClone(env.allocator),
    };
}

/// $eq: compare two values for equality
pub fn eq_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len != 2) return error.ArityError;
    const left = try env.eval(args[0]);
    const right = try env.eval(args[1]);
    return .{ .bool = left.eql(right) };
}

/// $cond: multi-branch conditional
pub fn cond_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .null;
    if (args.len % 2 == 0) {
        // Pairs only
        var i: usize = 0;
        while (i < args.len) : (i += 2) {
            const cond_val = try env.eval(args[i]);
            if (cond_val.isTruthy()) {
                return env.eval(args[i + 1]);
            }
        }
        return .null;
    } else {
        // With default (last arg)
        const default_arg = args[args.len - 1];
        var i: usize = 0;
        while (i < args.len - 1) : (i += 2) {
            const cond_val = try env.eval(args[i]);
            if (cond_val.isTruthy()) {
                return env.eval(args[i + 1]);
            }
        }
        return env.eval(default_arg);
    }
}
/// $head: get first element of list (car)
pub fn head_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return error.ArityError;
    const val = try env.eval(args[0]);
    if (val != .array) return error.TypeError;
    if (val.array.items.len == 0) return error.ValueError;
    return val.array.items[0].deepClone(env.allocator);
}

/// $tail: get rest of list (cdr)
pub fn tail_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return error.ArityError;
    const val = try env.eval(args[0]);
    if (val != .array) return error.TypeError;
    if (val.array.items.len <= 1) {
        return .{ .array = .empty };
    }
    var result: std.ArrayList(JseValue) = .empty;
    try result.ensureTotalCapacity(env.allocator, val.array.items.len - 1);
    for (val.array.items[1..]) |item| {
        result.appendAssumeCapacity(try item.deepClone(env.allocator));
    }
    return .{ .array = result };
}
/// $atom?: check if value is a JSON atom (number, string, bool, null)
pub fn atomp_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return error.ArityError;
    const val = try env.eval(args[0]);
    return .{ .bool = switch (val) {
        .null, .bool, .integer, .float, .string => true,
        else => false,
    } };
}
/// $cons: prepend element to list
pub fn cons_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len != 2) return error.ArityError;
    const elem = try env.eval(args[0]);
    const lst = try env.eval(args[1]);
    if (lst != .array) return error.TypeError;

    var result: std.ArrayList(JseValue) = .empty;
    try result.ensureTotalCapacity(env.allocator, 1 + lst.array.items.len);
    result.appendAssumeCapacity(try elem.deepClone(env.allocator));
    for (lst.array.items) |item| {
        result.appendAssumeCapacity(try item.deepClone(env.allocator));
    }
    return .{ .array = result };
}

pub const BUILTIN_FUNCTORS = [_]struct { []const u8, core.FunctorFn }{
    .{ "$quote", quote_fn },
    .{ "$eq", eq_fn },
    .{ "$cond", cond_fn },
    .{ "$head", head_fn },
    .{ "$tail", tail_fn },
    .{ "$atom?", atomp_fn },
    .{ "$cons", cons_fn },
};
