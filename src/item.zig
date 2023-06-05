const std = @import("std");

test "a" {
    var x: [3]u2 = undefined;
    x[0] = 1;
    x[1] = 1;
    x[2] = 2;
    var k = @bitCast(u6, x[0..3].*);
    _ = k;
}
