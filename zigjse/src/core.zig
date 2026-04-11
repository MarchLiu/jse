const std = @import("std");
const Allocator = std.mem.Allocator;
const JseValue = @import("value.zig").JseValue;

pub const JseError = error{
    OutOfMemory,
    ParseError,
    EvalError,
    ArityError,
    TypeError,
    ValueError,
    IndexError,
    SymbolNotFound,
    DuplicateSymbol,
    MultipleOperatorKeys,
    UnknownError,
};

pub const FunctorFn = *const fn (*Env, []const *AstNode) JseError!JseValue;

pub const ObjectPair = struct {
    key: []const u8,
    value: *AstNode,
};

pub const LambdaData = struct {
    params: std.ArrayList([]const u8),
    body: *AstNode,
    closure_env: *Env,
};

pub const AstNode = union(enum) {
    literal: struct { value: JseValue },
    symbol: struct { name: []const u8 },
    array_node: struct { elements: std.ArrayList(*AstNode) },
    object_node: struct { pairs: std.ArrayList(ObjectPair) },
    expression: struct {
        operator: []const u8,
        value: *AstNode,
        metadata: std.StringHashMap(*AstNode),
    },
    quote: struct { value: JseValue },

    pub fn apply(self: *AstNode, env: *Env) JseError!JseValue {
        return switch (self.*) {
            .literal => |lit| try lit.value.deepClone(env.allocator),
            .symbol => |sym| blk: {
                if (env.resolve(sym.name)) |val| {
                    break :blk try val.deepClone(env.allocator);
                }
                break :blk JseValue.null;
            },
            .quote => |q| try q.value.deepClone(env.allocator),
            .array_node => |arr| {
                var result: std.ArrayList(JseValue) = .empty;
                try result.ensureTotalCapacity(env.allocator, arr.elements.items.len);
                for (arr.elements.items) |elem| {
                    result.appendAssumeCapacity(try deepEval(env, elem));
                }
                return .{ .array = result };
            },
            .object_node => |obj| {
                var result = std.StringHashMap(JseValue).init(env.allocator);
                for (obj.pairs.items) |pair| {
                    const key_copy = try env.allocator.dupe(u8, pair.key);
                    const val = try deepEval(env, pair.value);
                    try result.put(key_copy, val);
                }
                return .{ .object = result };
            },
            .expression => |expr| {
                // Set metadata if present
                if (expr.metadata.count() > 0) {
                    env.setMeta(&expr.metadata);
                    defer env.clearMeta();
                }

                const functor = env.resolveFunctor(expr.operator) orelse return error.SymbolNotFound;
                env.current_functor_name = expr.operator;
                defer env.current_functor_name = null;

                // The value is the argument(s) to the functor
                switch (expr.value.*) {
                    .array_node => |arr| {
                        // Special cases: these functors handle their own arg evaluation
                        if (std.mem.eql(u8, expr.operator, "$quote") or
                            std.mem.eql(u8, expr.operator, "$cond") or
                            std.mem.eql(u8, expr.operator, "$lambda") or
                            std.mem.eql(u8, expr.operator, "$def") or
                            std.mem.eql(u8, expr.operator, "$defn") or
                            std.mem.eql(u8, expr.operator, "$eval"))
                        {
                            return functor(env, arr.elements.items);
                        }

                        // Default: evaluate all arguments before passing
                        const eval_args = try env.arena_allocator.alloc(*AstNode, arr.elements.items.len);
                        for (arr.elements.items, 0..) |elem, i| {
                            const val = try deepEval(env, elem);
                            const lit = try env.arena_allocator.create(AstNode);
                            lit.* = .{ .literal = .{ .value = val } };
                            eval_args[i] = lit;
                        }
                        return functor(env, eval_args);
                    },
                    else => {
                        // Single argument: evaluate and wrap
                        const val = try env.eval(expr.value);
                        const lit_node = try env.arena_allocator.create(AstNode);
                        lit_node.* = .{ .literal = .{ .value = val } };
                        const args = try env.arena_allocator.alloc(*AstNode, 1);
                        args[0] = lit_node;
                        return functor(env, args);
                    },
                }
            },
        };
    }
};

fn deepEval(env: *Env, node: *AstNode) JseError!JseValue {
    const evaluated = try env.eval(node);
    return switch (evaluated) {
        .array => |arr| {
            var result: std.ArrayList(JseValue) = .empty;
            try result.ensureTotalCapacity(env.allocator, arr.items.len);
            for (arr.items) |item| {
                switch (item) {
                    .array => {
                        var tmp = AstNode{ .literal = .{ .value = item } };
                        result.appendAssumeCapacity(try deepEval(env, &tmp));
                    },
                    else => result.appendAssumeCapacity(try item.deepClone(env.allocator)),
                }
            }
            return .{ .array = result };
        },
        .object => |obj| {
            var result = std.StringHashMap(JseValue).init(env.allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key_copy = try env.allocator.dupe(u8, entry.key_ptr.*);
                try result.put(key_copy, try entry.value_ptr.*.deepClone(env.allocator));
            }
            return .{ .object = result };
        },
        else => evaluated,
    };
}

pub const Env = struct {
    parent: ?*Env,
    allocator: Allocator,
    arena_allocator: Allocator,
    bindings: std.StringHashMap(JseValue),
    functors: std.StringHashMap(FunctorFn),
    lambdas: std.StringHashMap(LambdaData),
    current_meta: ?*const std.StringHashMap(*AstNode),
    current_functor_name: ?[]const u8,

    pub fn init(allocator: Allocator, arena: Allocator) Env {
        return .{
            .parent = null,
            .allocator = allocator,
            .arena_allocator = arena,
            .bindings = std.StringHashMap(JseValue).init(allocator),
            .functors = std.StringHashMap(FunctorFn).init(allocator),
            .lambdas = std.StringHashMap(LambdaData).init(allocator),
            .current_meta = null,
            .current_functor_name = null,
        };
    }

    pub fn initWithParent(allocator: Allocator, arena: Allocator, parent: *Env) Env {
        return .{
            .parent = parent,
            .allocator = allocator,
            .arena_allocator = arena,
            .bindings = std.StringHashMap(JseValue).init(allocator),
            .functors = std.StringHashMap(FunctorFn).init(allocator),
            .lambdas = std.StringHashMap(LambdaData).init(allocator),
            .current_meta = null,
            .current_functor_name = null,
        };
    }

    pub fn deinit(self: *Env) void {
        // Free binding keys and values
        var bind_it = self.bindings.iterator();
        while (bind_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deepFree(self.allocator);
        }
        self.bindings.deinit();

        // Free functor keys
        var func_it = self.functors.iterator();
        while (func_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.functors.deinit();

        // Free lambda keys and param strings
        var lam_it = self.lambdas.iterator();
        while (lam_it.next()) |entry| {
            for (entry.value_ptr.params.items) |p| {
                self.allocator.free(p);
            }
            entry.value_ptr.params.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.lambdas.deinit();
    }

    pub fn resolve(self: *Env, symbol: []const u8) ?JseValue {
        if (self.bindings.get(symbol)) |val| return val;
        if (self.parent) |p| return p.resolve(symbol);
        return null;
    }
    pub fn resolveFunctor(self: *Env, name: []const u8) ?FunctorFn {
        if (self.functors.get(name)) |fn_ptr| return fn_ptr;
        if (self.parent) |p| return p.resolveFunctor(name);
        return null;
    }
    pub fn register(self: *Env, name: []const u8, value: JseValue) JseError!void {
        if (self.bindings.contains(name)) return error.DuplicateSymbol;
        const name_copy = try self.allocator.dupe(u8, name);
        try self.bindings.put(name_copy, value);
    }
    pub fn set(self: *Env, name: []const u8, value: JseValue) JseError!void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.bindings.put(name_copy, value);
    }
    pub fn registerFunctor(self: *Env, name: []const u8, functor: FunctorFn) JseError!void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.functors.put(name_copy, functor);
    }
    pub fn registerLambda(self: *Env, name: []const u8, params: std.ArrayList([]const u8), body: *AstNode, closure_env: *Env) JseError!void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.lambdas.put(name_copy, .{
            .params = params,
            .body = body,
            .closure_env = closure_env,
        });
    }
    pub fn resolveLambda(self: *Env, name: []const u8) ?LambdaData {
        if (self.lambdas.get(name)) |data| return data;
        if (self.parent) |p| return p.resolveLambda(name);
        return null;
    }
    pub fn exists(self: *Env, name: []const u8) bool {
        if (self.bindings.contains(name)) return true;
        if (self.parent) |p| return p.exists(name);
        return false;
    }
    pub fn getMeta(self: *Env) ?*const std.StringHashMap(*AstNode) {
        return self.current_meta;
    }
    pub fn setMeta(self: *Env, meta: ?*const std.StringHashMap(*AstNode)) void {
        self.current_meta = meta;
    }
    pub fn clearMeta(self: *Env) void {
        self.current_meta = null;
    }
    pub fn eval(self: *Env, node: *AstNode) JseError!JseValue {
        return node.apply(self);
    }
    pub fn loadFunctors(self: *Env, modules: []const struct { []const u8, FunctorFn }) JseError!void {
        for (modules) |module| {
            try self.registerFunctor(module[0], module[1]);
        }
    }
};

pub fn lambdaDispatch(env: *Env, args: []const *AstNode) JseError!JseValue {
    const name = env.current_functor_name orelse return error.EvalError;
    const lam = env.resolveLambda(name) orelse return error.SymbolNotFound;
    if (args.len != lam.params.items.len) return error.ArityError;
    var child_env = Env.initWithParent(env.allocator, env.arena_allocator, lam.closure_env);
    defer child_env.deinit();
    for (lam.params.items, args) |param, arg| {
        const val = try env.eval(arg);
        try child_env.set(param, val);
    }
    return child_env.eval(lam.body);
}
