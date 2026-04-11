const std = @import("std");
const zigjse = @import("zigjse");

fn freeResult(result: zigjse.JseValue) void {
    var r = result;
    r.deepFree(std.testing.allocator);
}

test "number literal" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("42");
    defer freeResult(result);
    try std.testing.expect(result == .integer and result.integer == 42);
}

test "float literal" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("3.14");
    defer freeResult(result);
    try std.testing.expect(result == .float and result.float == 3.14);
}

test "string literal" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("\"hello\"");
    defer freeResult(result);
    try std.testing.expect(result == .string and std.mem.eql(u8, result.string, "hello"));
}

test "boolean literal" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result_true = try engine.execute("true");
    defer freeResult(result_true);
    try std.testing.expect(result_true == .bool and result_true.bool == true);

    const result_false = try engine.execute("false");
    defer freeResult(result_false);
    try std.testing.expect(result_false == .bool and result_false.bool == false);
}

test "null literal" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("null");
    defer freeResult(result);
    try std.testing.expect(result == .null);
}

test "$eq basic" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$eq\": [1, 1]}");
    defer freeResult(result);
    try std.testing.expect(result == .bool and result.bool == true);

    const result2 = try engine.execute("{\"$eq\": [1, 2]}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .bool and result2.bool == false);
}

test "$cond basic" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$cond\": [true, \"yes\", false, \"no\"]}");
    defer freeResult(result);
    try std.testing.expect(result == .string and std.mem.eql(u8, result.string, "yes"));

    const result2 = try engine.execute("{\"$cond\": [false, \"no\", \"default\"]}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .string and std.mem.eql(u8, result2.string, "default"));
}

test "$head and $tail" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$head\": [[1, 2, 3]]}");
    defer freeResult(result);
    try std.testing.expect(result == .integer and result.integer == 1);

    const result2 = try engine.execute("{\"$tail\": [[1, 2, 3]]}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .array and result2.array.items.len == 2);
    try std.testing.expect(result2.array.items[0].integer == 2);
}

test "$atom? check" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$atom?\": 42}");
    defer freeResult(result);
    try std.testing.expect(result == .bool and result.bool == true);

    const result2 = try engine.execute("{\"$atom?\": [[1, 2]]}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .bool and result2.bool == false);
}

test "$cons check" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$cons\": [1, [2, 3]]}");
    defer freeResult(result);
    try std.testing.expect(result == .array and result.array.items.len == 3);
    try std.testing.expect(result.array.items[0].integer == 1);
    try std.testing.expect(result.array.items[1].integer == 2);
}
