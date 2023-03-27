const std = @import("std");
const math = std.math;

/// Area 100@100 -> 600@600 = 500x500 -> 20x20
/// 
///

const GridTranslator = struct {
  step_width: f32 = 0,
  step_height: f32 = 0,
  columns: usize,
  rows: usize,

  const Self = @This();

  pub fn init(columns: usize, rows: usize, width: f32, height: f32) Self {
    var self = Self{
      .columns = columns,
      .rows = rows,
    };

    self.update(width, height);

    return self;
  }

  pub fn update(self: *Self, width: f32, height: f32) void {
    self.step_width = width / @intToFloat(f32, self.columns);
    self.step_height = height / @intToFloat(f32, self.rows);
  }

  pub fn indexAt(self: *const Self, x: f32, y: f32) !usize {
    const xPos = try math.divTrunc(f32, x, self.step_width);
    const yPos = try math.divTrunc(f32, y, self.step_height);
    var pos = @floatToInt(usize, xPos) + (@floatToInt(usize, yPos) * self.columns);
    return math.min(pos, self.columns * self.rows - 1);
  }
};


fn expectEqual(comptime T: type, expected: T, actual: T) !void {
  return std.testing.expectEqual(expected, actual);
}

test "grid" {
  var grid = GridTranslator.init(10, 10, 1024, 640);

  var pos = try grid.indexAt(1.0, 1.0);
  try expectEqual(usize, 0, pos);

  pos = try grid.indexAt(125.0, 1.0);
  try expectEqual(usize, 1, pos);

  pos = try grid.indexAt(0.0, 65.0);
  try expectEqual(usize, 10, pos);

  pos = try grid.indexAt(125.0, 65.0);
  try expectEqual(usize, 11, pos);

  pos = try grid.indexAt(1023.0, 639.0);
  try expectEqual(usize, 99, pos);

  pos = try grid.indexAt(1024.0, 640.0);
  try expectEqual(usize, 99, pos);
}