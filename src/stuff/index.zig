// const std = @import("std");

// pub fn ArchetypeIndex(comptime Tag: type, comptime Field: type) type {
//     return struct {
//         const ComponentCount = std.meta.fields(Tag).len;
//         const Set = std.AutoHashMapUnmanaged(u16, void);
//         const Map = std.AutoHashMapUnmanaged(usize, Set);
//         const WildcardMap = std.AutoArrayHashMapUnmanaged(usize, usize);
//         const Packer = componentId.ComponentId(Field);

//         allocator: Allocator,
//         map: Map = .{},

//         const Self = @This();

//         pub fn init(allocator: Allocator) Self {
//             return Self{ .allocator = allocator };
//         }

//         pub fn deinit(self: *Self) void {
//             var it = self.map.valueIterator();
//             while (it.next()) |value_ptr| {
//                 value_ptr.deinit(self.allocator);
//             }
//             self.map.deinit(self.allocator);
//         }

//         fn addEntry(self: *Self, component_id: usize, storage_index: u16) !void {
//             var entry = try self.map.getOrPut(self.allocator, component_id);
//             if (!entry.found_existing) {
//                 entry.value_ptr.* = .{};
//             }
//             try entry.value_ptr.put(self.allocator, storage_index, {});
//         }

//         pub fn append(self: *Self, component_id: usize, storage_index: u16) !void {
//             try self.addEntry(component_id, storage_index);
//             if (component_id < ComponentCount) return;
//             const wildcard_id = Packer.pairToWildcard(@intCast(u32, component_id));
//             try self.addEntry(wildcard_id, storage_index);
//         }

//         pub fn register(self: *Self, comptime T: type, component_id: usize, storage_index: u16) !void {
//             _ = T;
//             return self.append(component_id, storage_index);
//         }

//         pub fn IndexIterator(comptime T: type) type {
//             return struct {
//                 const fields = std.meta.fields(T);
//                 const identifiers = blk: {
//                     var buf: [fields.len]Packer.ComponentIdSize = undefined;
//                     inline for (fields, 0..) |field, index| {
//                         const value = Packer.fromType(field.type, field.name);
//                         buf[index] = value;
//                     }
//                     break :blk buf;
//                 };
//                 indexes: *const Self,
//                 iterator: Self.Set.KeyIterator = undefined,

//                 const Iterator = @This();

//                 pub fn init(indexes: *const Self) Iterator {
//                     const ix = fields.len - 1;
//                     return .{
//                         .indexes = indexes,
//                         .iterator = indexes.getSetIterator(fields[ix].type, identifiers[ix]),
//                     };
//                 }

//                 pub fn next(it: *Iterator) ?u16 {
//                     loop: while (it.iterator.next()) |archetype| {
//                         inline for (1..fields.len) |fIndex| {
//                             const index = fields.len - fIndex - 1;
//                             const id = identifiers[index];
//                             if (!it.haveItem(id, archetype)) continue :loop;
//                         }
//                         return archetype;
//                     }
//                     return null;
//                 }
//             };
//         }
//     };
// }
