const std = @import("std");
const JseValue = @import("../value.zig").JseValue;
const core = @import("../core.zig");
const lambdaDispatch = core.lambdaDispatch;

pub fn apply_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 2) return error.ArityError;
    const functor_val = try env.eval(args[0]);
    const arglist_val = try env.eval(args[1]);

    if (functor_val != .string) return error.TypeError;
    if (arglist_val != .array) return error.TypeError;

    const name = functor_val.string;
    const fn_ptr = env.resolveFunctor(name) orelse return error.SymbolNotFound;

    var arg_nodes = try env.arena_allocator.alloc(*core.AstNode, arglist_val.array.items.len);
    for (arglist_val.array.items, 0..) |val, i| {
        const lit = try env.arena_allocator.create(core.AstNode);
        lit.* = .{ .literal = .{ .value = try val.deepClone(env.allocator) } };
        arg_nodes[i] = lit;
    }

    env.current_functor_name = name;
    defer env.current_functor_name = null;
    return fn_ptr(env, arg_nodes);
}

pub fn eval_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len == 0) return error.ArityError;
    return env.eval(args[0]);
}

pub fn lambda_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 2) return error.ArityError;

    const params_node = args[0];
    const body = args[1];

    var param_names: std.ArrayList([]const u8) = .empty;

    if (params_node.* == .array_node) {
        for (params_node.array_node.elements.items) |elem| {
            if (elem.* == .symbol) {
                try param_names.append(env.allocator, try env.allocator.dupe(u8, elem.symbol.name));
            } else {
                return error.TypeError;
            }
        }
    } else if (params_node.* == .symbol) {
        try param_names.append(env.allocator, try env.allocator.dupe(u8, params_node.symbol.name));
    } else {
        return error.TypeError;
    }

    const lambda_name = try std.fmt.allocPrint(env.allocator, "$__lambda_{}", .{env.lambdas.count()});
    try env.registerLambda(lambda_name, param_names, body, env);
    try env.registerFunctor(lambda_name, lambdaDispatch);

    return .{ .string = lambda_name };
}

pub fn def_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len != 2) return error.ArityError;

    const name_node = args[0];
    const name: []const u8 = switch (name_node.*) {
        .symbol => |s| s.name,
        else => return error.TypeError,
    };

    const value = try env.eval(args[1]);
    try env.register(name, value);
    return value;
}

pub fn defn_fn(env: *core.Env, args: []const *core.AstNode) core.JseError!JseValue {
    if (args.len < 3) return error.ArityError;

    const name_node = args[0];
    const name: []const u8 = switch (name_node.*) {
        .symbol => |s| s.name,
        else => return error.TypeError,
    };

    const params_node = args[1];
    var param_names: std.ArrayList([]const u8) = .empty;
    if (params_node.* == .array_node) {
        for (params_node.array_node.elements.items) |elem| {
            if (elem.* == .symbol) {
                try param_names.append(env.allocator, try env.allocator.dupe(u8, elem.symbol.name));
            } else {
                return error.TypeError;
            }
        }
    } else {
        return error.TypeError;
    }

    const body = args[2];

    const name_copy = try env.allocator.dupe(u8, name);
    try env.registerLambda(name_copy, param_names, body, env);
    try env.registerFunctor(name_copy, lambdaDispatch);

    return .{ .string = name_copy };
}

pub const LISP_FUNCTORS = [_]struct { []const u8, core.FunctorFn }{
    .{ "$apply", apply_fn },
    .{ "$eval", eval_fn },
    .{ "$lambda", lambda_fn },
    .{ "$def", def_fn },
    .{ "$defn", defn_fn },
};
