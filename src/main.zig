const std = @import("std");
const testing = std.testing;
const reflection = @import("reflection.zig");


pub fn QueryCache(comptime types: []const type) type {
    const Cache = reflection.typesToHolder(types);
    return struct {
        allocator: std.mem.Allocator,
        cache: Cache = {},
        
        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator
            };
        } 

        pub fn get(self: *Self, T: type) ?T {
            return @field(self.cache, @typeName(T));
        }
    };
}

// const BufferHolder = struct {
//     const Map = std.AutoArrayHashMap(usize, []u8);
//     map: Map,

//     const Self = @This();
//     pub fn init(allocator: std.mem.Allocator) Self {
//         return .{
//             .map = Map.init(allocator)
//         };
//     }

//     pub fn get(self: Self, T: type) ?T {
//         var data = self.map.get(reflection.typeId(T));
//         if (data) | d | {
//             return @ptrCast(*T, @alignCast(@alignOf(T), &data));
//         }
//         return null;
//     }

//     pub fn set(self: Self, T: type, value: *T) !void {

//     }
// };
