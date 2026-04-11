const std = @import("std");
const Allocator = std.mem.Allocator;
const JseValue = @import("value.zig").JseValue;
const core = @import("core.zig");

/// Check if string is a JSE symbol: starts with $ but not $$, and is not $*
pub fn isSymbol(s: []const u8) bool {
    if (s.len == 0) return false;
    if (std.mem.eql(u8, s, "$*")) return false;
    return s[0] == '$' and (s.len < 2 or s[1] != '$');
}

/// Unescape $$-prefixed string: "$$x" -> "$x"
pub fn unescape(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '$' and s[1] == '$') {
        return s[1..];
    }
    return s;
}

pub const Parser = struct {
    allocator: Allocator,
    arena: Allocator,
    env: *core.Env,

    pub fn init(allocator: Allocator, arena: Allocator, env: *core.Env) Parser {
        return .{
            .allocator = allocator,
            .arena = arena,
            .env = env,
        };
    }

    /// Parse a JseValue (already converted from JSON) into an AST node
    pub fn parse(self: *Parser, value: JseValue) !*core.AstNode {
        return switch (value) {
            .null, .bool, .integer, .float => {
                const node = try self.arena.create(core.AstNode);
                node.* = .{ .literal = .{ .value = try value.deepClone(self.allocator) } };
                return node;
            },
            .string => |s| {
                const node = try self.arena.create(core.AstNode);
                if (isSymbol(s)) {
                    node.* = .{ .symbol = .{ .name = try self.allocator.dupe(u8, s) } };
                } else {
                    node.* = .{ .literal = .{ .value = .{ .string = try self.allocator.dupe(u8, unescape(s)) } } };
                }
                return node;
            },
            .array => |arr| self.parseList(arr.items),
            .object => |obj| self.parseDict(obj),
        };
    }

    /// Parse a std.json.Value directly (convenience)
    pub fn parseJson(self: *Parser, jv: std.json.Value) !*core.AstNode {
        const val = try JseValue.fromJson(self.allocator, jv);
        return self.parse(val);
    }

    fn parseList(self: *Parser, items: []JseValue) core.JseError!*core.AstNode {
        if (items.len == 0) {
            const node = try self.arena.create(core.AstNode);
            node.* = .{ .array_node = .{ .elements = .empty } };
            return node;
        }

        // Special case: $quote
        if (items[0] == .string and std.mem.eql(u8, items[0].string, "$quote")) {
            const node = try self.arena.create(core.AstNode);
            const quoted = if (items.len > 1) try items[1].deepClone(self.allocator) else JseValue.null;
            node.* = .{ .quote = .{ .value = quoted } };
            return node;
        }

        // Check if first element is a symbol (function call form)
        if (items[0] == .string and isSymbol(items[0].string)) {
            const operator = try self.allocator.dupe(u8, items[0].string);
            var elements: std.ArrayList(*core.AstNode) = .empty;
            var i: usize = 1;
            while (i < items.len) : (i += 1) {
                const parsed = try self.parse(items[i]);
                try elements.append(self.allocator, parsed);
            }

            // Wrap elements as an array_node value for the ExpressionData
            const value_node = try self.arena.create(core.AstNode);
            value_node.* = .{ .array_node = .{ .elements = elements } };

            const node = try self.arena.create(core.AstNode);
            node.* = .{ .expression = .{
                .operator = operator,
                .value = value_node,
                .metadata = std.StringHashMap(*core.AstNode).init(self.allocator),
            } };
            return node;
        }

        // Regular array: parse all elements
        var elements: std.ArrayList(*core.AstNode) = .empty;
        for (items) |item| {
            try elements.append(self.allocator, try self.parse(item));
        }
        const node = try self.arena.create(core.AstNode);
        node.* = .{ .array_node = .{ .elements = elements } };
        return node;
    }

    fn parseDict(self: *Parser, obj: std.StringHashMap(JseValue)) core.JseError!*core.AstNode {
        // Find symbol keys
        var symbol_keys: std.ArrayList([]const u8) = .empty;
        defer symbol_keys.deinit(self.allocator);

        var it = obj.iterator();
        while (it.next()) |entry| {
            if (isSymbol(entry.key_ptr.*)) {
                try symbol_keys.append(self.allocator, entry.key_ptr.*);
            }
        }

        if (symbol_keys.items.len == 0) {
            // Regular object: parse all values
            var pairs: std.ArrayList(core.ObjectPair) = .empty;
            it = obj.iterator();
            while (it.next()) |entry| {
                const parsed_key = try self.allocator.dupe(u8, unescape(entry.key_ptr.*));
                const parsed_value = try self.parse(entry.value_ptr.*);
                try pairs.append(self.allocator, .{ .key = parsed_key, .value = parsed_value });
            }
            const node = try self.arena.create(core.AstNode);
            node.* = .{ .object_node = .{ .pairs = pairs } };
            return node;
        }

        if (symbol_keys.items.len == 1) {
            const operator_key = symbol_keys.items[0];
            const operator = try self.allocator.dupe(u8, operator_key);

            // Special case: $quote
            if (std.mem.eql(u8, operator_key, "$quote")) {
                const node = try self.arena.create(core.AstNode);
                const quoted_val = obj.get(operator_key) orelse JseValue.null;
                node.* = .{ .quote = .{ .value = try quoted_val.deepClone(self.allocator) } };
                return node;
            }

            // Parse the operator value
            const op_value = obj.get(operator_key) orelse JseValue.null;
            const parsed_value = try self.parse(op_value);

            // Parse metadata (other keys)
            var metadata = std.StringHashMap(*core.AstNode).init(self.allocator);
            it = obj.iterator();
            while (it.next()) |entry| {
                if (!std.mem.eql(u8, entry.key_ptr.*, operator_key)) {
                    const meta_key = try self.allocator.dupe(u8, unescape(entry.key_ptr.*));
                    const meta_value = try self.parse(entry.value_ptr.*);
                    try metadata.put(meta_key, meta_value);
                }
            }

            const node = try self.arena.create(core.AstNode);
            node.* = .{ .expression = .{
                .operator = operator,
                .value = parsed_value,
                .metadata = metadata,
            } };
            return node;
        }

        // Multiple symbol keys - error
        return error.MultipleOperatorKeys;
    }
};
