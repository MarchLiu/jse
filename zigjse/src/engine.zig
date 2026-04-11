const std = @import("std");
const Allocator = std.mem.Allocator;
const JseValue = @import("value.zig").JseValue;
const core = @import("core.zig");
const Parser = @import("parser.zig").Parser;
const builtin = @import("functors/builtin.zig");
const utils = @import("functors/utils.zig");
const lisp = @import("functors/lisp.zig");
const sql = @import("functors/sql.zig");

pub const Engine = struct {
    allocator: Allocator,
    env: *core.Env,

    pub fn init(allocator: Allocator) !*Engine {
        const env = try allocator.create(core.Env);
        env.* = core.Env.init(allocator, allocator);
        try env.loadFunctors(&builtin.BUILTIN_FUNCTORS);
        try env.loadFunctors(&utils.UTILS_FUNCTORS);
        try env.loadFunctors(&lisp.LISP_FUNCTORS);
        try env.loadFunctors(&sql.SQL_FUNCTORS);

        const engine = try allocator.create(Engine);
        engine.* = .{
            .allocator = allocator,
            .env = env,
        };
        return engine;
    }

    pub fn deinit(self: *Engine) void {
        self.env.deinit();
        self.allocator.destroy(self.env);
        self.allocator.destroy(self);
    }

    pub fn execute(self: *Engine, json_string: []const u8) !JseValue {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();

        const parsed = try std.json.parseFromSlice(std.json.Value, arena_allocator, json_string, .{});

        const jv = try JseValue.fromJson(arena_allocator, parsed.value);
        const result = try self.executeValueWithArena(arena_allocator, jv);
        const owned = try result.deepClone(self.allocator);
        parsed.deinit();
        arena.deinit();
        return owned;
    }

    pub fn loadAllFunctors(self: *Engine) !void {
        _ = self;
    }

    pub fn executeValue(self: *Engine, value: JseValue) !JseValue {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();

        const cloned = try value.deepClone(arena_allocator);
        const result = try self.executeValueWithArena(arena_allocator, cloned);
        const owned = try result.deepClone(self.allocator);
        arena.deinit();
        return owned;
    }

    fn executeValueWithArena(self: *Engine, arena_allocator: Allocator, value: JseValue) !JseValue {
        var exec_env = core.Env.initWithParent(arena_allocator, arena_allocator, self.env);
        defer exec_env.deinit();

        var parser = Parser.init(arena_allocator, arena_allocator, &exec_env);
        const ast = try parser.parse(value);
        return exec_env.eval(ast);
    }
};
