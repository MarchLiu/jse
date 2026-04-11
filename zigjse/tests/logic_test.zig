const std = @import("std");
const zigjse = @import("zigjse");

fn freeResult(result: zigjse.JseValue) void {
    var r = result;
    r.deepFree(std.testing.allocator);
}

test "$eq check" {
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

test "$not check" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$not\": true}");
    defer freeResult(result);
    try std.testing.expect(result == .bool and result.bool == false);

    const result2 = try engine.execute("{\"$not\": false}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .bool and result2.bool == true);
}

test "$and check" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$and\": [true, true, true]}");
    defer freeResult(result);
    try std.testing.expect(result == .bool and result.bool == true);

    const result2 = try engine.execute("{\"$and\": [true, false, true]}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .bool and result2.bool == false);
}

test "$or check" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const result = try engine.execute("{\"$or\": [false, false, true]}");
    defer freeResult(result);
    try std.testing.expect(result == .bool and result.bool == true);

    const result2 = try engine.execute("{\"$or\": [false, false, false]}");
    defer freeResult(result2);
    try std.testing.expect(result2 == .bool and result2.bool == false);
}

test "nested logic" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    // $or($and(true, $not(false)), $and(false, true))
    const expr =
        \\{"$or": [
        \\  {"$and": [true, {"$not": false}]},
        \\  {"$and": [false, true]}
        \\]}
    ;
    const result = try engine.execute(expr);
    defer freeResult(result);
    try std.testing.expect(result == .bool and result.bool == true);
}
