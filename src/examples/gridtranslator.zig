const std = @import("std");
const math = std.math;

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

  pub fn translate(self: *const Self, x: f32, y: f32) !usize {
    const xPos = try math.divTrunc(f32, x, self.step_width);
    const yPos = try math.divTrunc(f32, y, self.step_height);
    var pos = @floatToInt(usize, xPos) + (@floatToInt(usize, yPos) * self.columns);
    return math.min(pos, self.columns * self.rows - 1);
  }
};


fn expectUsize(expected: usize, actual: usize) !void {
  return std.testing.expectEqual(expected, actual);
}

test "grid" {
  var grid = GridTranslator.init(10, 10, 1024, 640);

  var pos = try grid.translate(1.0, 1.0);
  try expectUsize(0, pos);

  pos = try grid.translate(125.0, 1.0);
  try expectUsize(1, pos);

  pos = try grid.translate(0.0, 65.0);
  try expectUsize(10, pos);

  pos = try grid.translate(125.0, 65.0);
  try expectUsize(11, pos);

  pos = try grid.translate(1023.0, 639.0);
  try expectUsize(99, pos);

  pos = try grid.translate(1024.0, 640.0);
  try expectUsize(99, pos);
}