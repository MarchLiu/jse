const std = @import("std");
const zigjse = @import("zigjse");

fn freeResult(result: zigjse.JseValue) void {
    var r = result;
    r.deepFree(std.testing.allocator);
}

test "basic query" {
    const engine = zigjse.Engine.init(std.testing.allocator) catch unreachable;
    defer engine.deinit();
    try engine.loadAllFunctors();

    const expr =
        \\{"$query": {"$quote": ["$pattern", "$*", "author of", "$*"]}}
    ;
    const result = try engine.execute(expr);
    defer freeResult(result);

    try std.testing.expect(result == .string);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "select") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "subject") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "author of") != null);
}
