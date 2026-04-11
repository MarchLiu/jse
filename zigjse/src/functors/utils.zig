const std = @import("std");
const JseValue = @import("../value.zig").JseValue;
const core = @import("../core.zig");

/// $not: logical negation
pub fn not_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .bool = true };
    const val = try env.eval(args[0]);
    return .{ .bool = !val.isTruthy() };
}

/// $list?: check if value is a list
pub fn listp_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .bool = false };
    const val = try env.eval(args[0]);
    return .{ .bool = val == .array };
}

/// $map?: check if value is a map
pub fn mapp_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .bool = false };
    const val = try env.eval(args[0]);
    return .{ .bool = val == .object };
}

/// $null?: check if value is null
pub fn nullp_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .bool = true };
    const val = try env.eval(args[0]);
    return .{ .bool = val == .null };
}

/// $get: get value from map or list by key/index
pub fn get_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 2) return error.ArityError;
    const collection = try env.eval(args[0]);
    const key = try env.eval(args[1]);

    switch (collection) {
        .object => {
            if (key != .string) return error.TypeError;
            if (collection.object.get(key.string)) |val| {
                return try val.deepClone(env.allocator);
            }
            return .null;
        },
        .array => |arr| {
            if (key != .integer) return error.TypeError;
            if (key.integer < 0 or key.integer >= @as(i64, @intCast(arr.items.len))) {
                return error.IndexError;
            }
            return try arr.items[@as(usize, @intCast(key.integer))].deepClone(env.allocator);
        },
        else => return error.TypeError,
    }
}

/// $set: set value in map or list (returns new modified copy)
pub fn set_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 3) return error.ArityError;
    const collection = try env.eval(args[0]);
    const key = try env.eval(args[1]);
    const value = try env.eval(args[2]);

    switch (collection) {
        .object => {
            if (key != .string) return error.TypeError;
            var cloned = try collection.deepClone(env.allocator);
            const key_copy = try env.allocator.dupe(u8, key.string);
            try cloned.object.put(key_copy, try value.deepClone(env.allocator));
            return cloned;
        },
        .array => |arr| {
            if (key != .integer) return error.TypeError;
            if (key.integer < 0 or key.integer >= @as(i64, @intCast(arr.items.len))) {
                return error.IndexError;
            }
            var cloned = try collection.deepClone(env.allocator);
            cloned.array.items[@as(usize, @intCast(key.integer))] = try value.deepClone(env.allocator);
            return cloned;
        },
        else => return error.TypeError,
    }
}

/// $del: delete key from map or index from list (returns new copy)
pub fn del_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 2) return error.ArityError;
    const collection = try env.eval(args[0]);
    const key = try env.eval(args[1]);

    switch (collection) {
        .object => {
            if (key != .string) return error.TypeError;
            var cloned = try collection.deepClone(env.allocator);
            _ = cloned.object.remove(key.string);
            return cloned;
        },
        .array => |arr| {
            if (key != .integer) return error.TypeError;
            const idx = @as(usize, @intCast(key.integer));
            if (key.integer < 0 or idx >= arr.items.len) return error.IndexError;
            var result: std.ArrayList(JseValue) = .empty;
            for (arr.items, 0..) |item, i| {
                if (i != idx) {
                    try result.append(env.allocator, try item.deepClone(env.allocator));
                }
            }
            return .{ .array = result };
        },
        else => return error.TypeError,
    }
}

/// $conj: append element to end of list
pub fn conj_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len != 2) return error.ArityError;
    const elem = try env.eval(args[0]);
    const lst = try env.eval(args[1]);
    if (lst != .array) return error.TypeError;

    var result: std.ArrayList(JseValue) = .empty;
    try result.ensureTotalCapacity(env.allocator, lst.array.items.len + 1);
    for (lst.array.items) |item| {
        result.appendAssumeCapacity(try item.deepClone(env.allocator));
    }
    result.appendAssumeCapacity(try elem.deepClone(env.allocator));
    return .{ .array = result };
}

/// $and: logical AND
pub fn and_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .bool = true };
    for (args) |arg| {
        const val = try env.eval(arg);
        if (!val.isTruthy()) return .{ .bool = false };
    }
    return .{ .bool = true };
}

/// $or: logical OR
pub fn or_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return .{ .bool = false };
    for (args) |arg| {
        const val = try env.eval(arg);
        if (val.isTruthy()) return .{ .bool = true };
    }
    return .{ .bool = false };
}

pub const UTILS_FUNCTORS = [_]struct { []const u8, core.FunctorFn }{
    .{ "$not", not_fn },
    .{ "$list?", listp_fn },
    .{ "$map?", mapp_fn },
    .{ "$null?", nullp_fn },
    .{ "$get", get_fn },
    .{ "$set", set_fn },
    .{ "$del", del_fn },
    .{ "$conj", conj_fn },
    .{ "$and", and_fn },
    .{ "$or", or_fn },
};
