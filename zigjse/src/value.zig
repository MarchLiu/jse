const std = @import("std");
const Allocator = std.mem.Allocator;

pub const JseValue = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: std.ArrayList(JseValue),
    object: std.StringHashMap(JseValue),

    pub fn deepClone(self: JseValue, allocator: Allocator) Allocator.Error!JseValue {
        return switch (self) {
            .null => JseValue.null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .array => |arr| {
                var new: std.ArrayList(JseValue) = .empty;
                try new.ensureTotalCapacity(allocator, arr.items.len);
                for (arr.items) |item| new.appendAssumeCapacity(try item.deepClone(allocator));
                return .{ .array = new };
            },
            .object => |obj| {
                var new = std.StringHashMap(JseValue).init(allocator);
                var it = obj.iterator();
                while (it.next()) |e| {
                    try new.put(try allocator.dupe(u8, e.key_ptr.*), try e.value_ptr.*.deepClone(allocator));
                }
                return .{ .object = new };
            },
        };
    }

    pub fn eql(a: JseValue, b: JseValue) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) {
            if (a == .integer and b == .float) return @as(f64, @floatFromInt(a.integer)) == b.float;
            if (a == .float and b == .integer) return a.float == @as(f64, @floatFromInt(b.integer));
            return false;
        }
        return switch (a) {
            .null => true,
            .bool => |v| v == b.bool,
            .integer => |v| v == b.integer,
            .float => |v| v == b.float,
            .string => |v| std.mem.eql(u8, v, b.string),
            .array => |v| {
                if (v.items.len != b.array.items.len) return false;
                for (v.items, b.array.items) |ai, bi| if (!ai.eql(bi)) return false;
                return true;
            },
            .object => |v| {
                if (v.count() != b.object.count()) return false;
                var it = v.iterator();
                while (it.next()) |e| {
                    const bv = b.object.get(e.key_ptr.*) orelse return false;
                    if (!e.value_ptr.*.eql(bv)) return false;
                }
                return true;
            },
        };
    }

    pub fn isTruthy(self: JseValue) bool {
        return switch (self) {
            .null => false,
            .bool => |b| b,
            .integer => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0,
            .array => |a| a.items.len > 0,
            .object => |o| o.count() > 0,
        };
    }

    pub fn deepFree(self: *JseValue, allocator: Allocator) void {
        switch (self.*) {
            .null, .bool, .integer, .float => {},
            .string => |s| allocator.free(s),
            .array => |*arr| {
                for (arr.items) |*item| item.deepFree(allocator);
                arr.deinit(allocator);
            },
            .object => |*obj| {
                var it = obj.iterator();
                while (it.next()) |e| {
                    allocator.free(e.key_ptr.*);
                    e.value_ptr.deepFree(allocator);
                }
                obj.deinit();
            },
        }
    }

    pub fn toJson(self: JseValue, allocator: Allocator) Allocator.Error!std.json.Value {
        return switch (self) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .array => |arr| {
                var list = std.json.Array.init(allocator);
                try list.ensureTotalCapacity(arr.items.len);
                for (arr.items) |item| list.appendAssumeCapacity(try item.toJson(allocator));
                return .{ .array = list };
            },
            .object => |obj| {
                var map = std.json.ObjectMap.init(allocator);
                var it = obj.iterator();
                while (it.next()) |e| {
                    try map.put(
                        try allocator.dupe(u8, e.key_ptr.*),
                        try e.value_ptr.*.toJson(allocator),
                    );
                }
                return .{ .object = map };
            },
        };
    }

    pub fn fromJson(allocator: Allocator, jv: std.json.Value) Allocator.Error!JseValue {
        return switch (jv) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .number_string => |ns| blk: {
                if (std.fmt.parseInt(i64, ns, 10)) |i| break :blk .{ .integer = i } else |_| {}
                break :blk .{ .float = std.fmt.parseFloat(f64, ns) catch return error.OutOfMemory };
            },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .array => |arr| {
                var list: std.ArrayList(JseValue) = .empty;
                try list.ensureTotalCapacity(allocator, arr.items.len);
                for (arr.items) |item| list.appendAssumeCapacity(try JseValue.fromJson(allocator, item));
                return .{ .array = list };
            },
            .object => |obj| {
                var map = std.StringHashMap(JseValue).init(allocator);
                var it = obj.iterator();
                while (it.next()) |e| {
                    try map.put(try allocator.dupe(u8, e.key_ptr.*), try JseValue.fromJson(allocator, e.value_ptr.*));
                }
                return .{ .object = map };
            },
        };
    }
};
