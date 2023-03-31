const std = @import("std");
const reflection = @import("reflection.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const builtin = @import("builtin");
const assert = std.debug.assert;
const ecs = @import("ecs.zig");
const autoHash = std.hash.autoHash;
const Wyhash = std.hash.Wyhash;

const is_debug = builtin.mode == .Debug;

const EntityID = ecs.EntityID;

comptime {
    std.debug.assert(@sizeOf(EntityID) != 0);
}

const TypeId = ecs.TypeId;
const typeId = ecs.typeId;

pub fn CreateColumn(comptime ColumnId: type) type {
    return struct {
        id: ColumnId,
        typeId: TypeId,
        size: u32,
        alignment: u16,
        offset: usize,

        const Self = @This();

        pub fn init(id: ColumnId, comptime component: type) Self {
            return .{
                .id = id,
                .typeId = typeId(component),
                .size = @sizeOf(component),
                .alignment = if (@sizeOf(component) == 0) 1 else @alignOf(component),
                .offset = undefined,
            };
        }
    };
}

/// Represents a single archetype, that is, entities which have the same exact set of component
/// types. When a component is added or removed from an entity, it's archetype changes.
///
/// Database equivalent: a table where rows are entities and columns are components (dense storage).
pub fn ArchetypeStorage(comptime ColumnId: type, comptime ComponentTag: type) type {
    return struct {
        allocator: Allocator,
        /// The hash of every component name in this archetype, i.e. the name of this archetype.
        hash: u64,
        /// The length of the table (used number of rows.)
        len: u32,
        /// The capacity of the table (allocated number of rows.)
        capacity: u32,
        /// Describes the columns stored in the `block` of memory, sorted by the smallest alignment
        /// value.
        columns: []Column,
        /// The block of memory where all entities of this archetype are actually stored. This memory is
        /// laid out as contiguous column values (i.e. the same way MultiArrayList works, SoA style)
        /// so `[col1_val1, col1_val2, col2_val1, col2_val2, ...]`. The number of rows is always
        /// identical (the `ArchetypeStorage.capacity`), and an "id" column is always present (the
        /// entity IDs stored in the table.) The value names, size, and alignments are described by the
        /// `ArchetypeStorage.columns` slice.
        ///
        /// When necessary, padding is added between the column value *arrays* in order to achieve
        /// alignment.
        block: []u8,

        const Self = @This();

        const PackedColumnId = @import("entities.zig").PackedComponentId(ComponentTag);
        pub const Column = CreateColumn(ColumnId);
        /// Calculates the storage.hash value. This is a hash of all the component names, and can
        /// effectively be used to uniquely identify this table within the database.
        pub fn calculateHash(storage: *Self) void {
            storage.hash = calculateHashInner(storage.columns);
        }

        fn calculateHashInner(columns: []const Column) u64 {
            var hasher = Wyhash.init(0);
            for (columns) |column| {
                hasher.update(std.mem.asBytes(&column.id));
            }
            return hasher.final();
        }

        pub fn init(allocator: Allocator, columns: []Column) Self {
            var hash = calculateHashInner(columns);
            var self = Self{
                .allocator = allocator,
                .len = 0,
                .capacity = 0,
                .columns = columns,
                .block = undefined,
                .hash = hash,
            };

            return self;
        }

        pub fn deinit(storage: *Self) void {
            if (storage.capacity > 0) {
                storage.allocator.free(storage.block);
            }
            storage.allocator.free(storage.columns);
            storage.len = 0;
        }

        // fn debugValidateRow(storage: *Self, row: anytype) void {
        //     inline for (std.meta.fields(@TypeOf(row)), 0..) |field, index| {
        //         const column = storage.columns[index];
        //         if (typeId(field.type) != column.typeId) {
        //           storage.dbg_panic(@typeName(field.type), @tagName(column.name));
        //         }
        //     }
        // }

        /// appends a new row to this table, with all undefined values.
        pub fn appendUndefined(storage: *Self) !u32 {
            try storage.ensureUnusedCapacity(1);
            assert(storage.len < storage.capacity);
            const row_index = storage.len;
            storage.len += 1;
            return row_index;
        }

        pub fn append(storage: *Self, row: anytype) !u32 {
            //if (is_debug) storage.debugValidateRow(row);

            var row_index = try storage.appendUndefined();
            storage.setRow(row_index, row);
            return row_index;
        }

        pub fn undoAppend(storage: *Self) void {
            storage.len -= 1;
        }

        /// Ensures there is enough unused capacity to store `num_rows`.
        pub fn ensureUnusedCapacity(storage: *Self, num_rows: usize) !void {
            return storage.ensureTotalCapacity(storage.len + num_rows);
        }

        /// Ensures the total capacity is enough to store `new_capacity` rows total.
        pub fn ensureTotalCapacity(storage: *Self, new_capacity: usize) !void {
            var better_capacity = storage.capacity;
            if (better_capacity >= new_capacity) return;

            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }

            return storage.setCapacity(better_capacity);
        }

        /// Sets the capacity to exactly `new_capacity` rows total
        ///
        /// Asserts `new_capacity >= storage.len`, if you want to shrink capacity then change the len
        /// yourself first.
        pub fn setCapacity(storage: *Self, new_capacity: usize) !void {
            assert(storage.capacity >= storage.len);

            // TODO: ensure columns are sorted by alignment

            var new_capacity_bytes: usize = 0;
            for (storage.columns) |*column| {
                const max_padding = column.alignment - 1;
                new_capacity_bytes += max_padding;
                new_capacity_bytes += new_capacity * column.size;
            }
            const new_block = try storage.allocator.alloc(u8, new_capacity_bytes);

            var offset: usize = 0;
            for (storage.columns) |*column| {
                const addr = @ptrToInt(&new_block[offset]);
                const aligned_addr = std.mem.alignForward(addr, column.alignment);
                const padding = aligned_addr - addr;
                offset += padding;
                if (storage.capacity > 0) {
                    const slice = storage.block[column.offset .. column.offset + storage.capacity * column.size];
                    mem.copy(u8, new_block[offset..], slice);
                }
                column.offset = offset;
                offset += new_capacity * column.size;
            }

            if (storage.capacity > 0) {
                storage.allocator.free(storage.block);
            }
            storage.block = new_block;
            storage.capacity = @intCast(u32, new_capacity);
        }

        /// Sets the entire row's values in the table.
        pub fn setRow(storage: *Self, row_index: u32, row: anytype) void {
            //if (is_debug) storage.debugValidateRow(row);
            const RowType = @TypeOf(row);
            inline for (std.meta.fields(RowType)) |field| {
                const ColumnType = field.type;
                if (@sizeOf(ColumnType) == 0) continue;

                const columnId = PackedColumnId.fromType(field.type, field.name);
                loop: for (storage.columns) |column| {
                    if (column.id != columnId) continue :loop;
                    const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                    columnValues[row_index] = @field(row, field.name);
                }
            }
        }

        /// Sets the value of the named components (columns) for the given row in the table.
        pub fn set(storage: *Self, row_index: u32, id: ColumnId, component: anytype) void {
            const ColumnType = @TypeOf(component);
            if (@sizeOf(ColumnType) == 0) return;
            for (storage.columns) |column| {
                if (column.id != id) continue;
                if (is_debug) {
                    if (typeId(ColumnType) != column.typeId) {
                        @panic("fixMe");
                        //storage.dbg_panic(@typeName(ColumnType), @tagName(column.name));
                    }
                }
                const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                columnValues[row_index] = component;
                return;
            }
            @panic("no such component");
        }

        // fn dbg_panic(storage: *Self, typeName: []const u8, tagName: []const u8) void {
        //     const msg = std.mem.concat(storage.allocator, u8, &.{
        //         "unexpected type: ", typeName, " expected: ", tagName,
        //     }) catch |err| @panic(@errorName(err));
        //     @panic(msg);
        // }

        pub fn get(storage: *Self, row_index: u32, id: ColumnId, comptime ColumnType: type) ?ColumnType {
            for (storage.columns) |column| {
                if (column.id != id) continue;
                if (@sizeOf(ColumnType) == 0) return {};
                // if (is_debug) {
                //     if (typeId(ColumnType) != column.typeId) {
                //         storage.dbg_panic(@typeName(ColumnType), @tagName(column.name));
                //     }
                // }
                const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                return columnValues[row_index];
            }
            return null;
        }

        pub fn getInto(storage: *Self, row_index: u32, comptime TValue: type) ?TValue {
            var data: TValue = undefined;
            inline for (std.meta.fields(TValue)) |field| {
                const f_info = @typeInfo(field.type);
                const isPointer = f_info == .Pointer;
                const ColumnType = if (!isPointer) field.type else f_info.Pointer.child;

                //const columnId = identifiers[index];
                const columnId = comptime if (std.meta.stringToEnum(ComponentTag, field.name)) |tag| @enumToInt(tag) else std.meta.fields(ComponentTag).len + @enumToInt(reflection.typeId(field.type));
                for (storage.columns) |column| {
                    if (column.id == columnId) {
                        const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                        @field(data, field.name) = if (isPointer) &columnValues[row_index] else columnValues[row_index];
                    }
                }
            }
            return data;
        }

        pub fn getRaw(storage: *Self, row_index: u32, id: ColumnId) []u8 {
            for (storage.columns) |column| {
                if (column.id != id) continue;
                const start = column.offset + (column.size * row_index);
                return storage.block[start .. start + (column.size)];
            }
            @panic("no such component");
        }

        pub fn setRaw(storage: *Self, row_index: u32, column: Column, component: []u8) !void {
            if (is_debug) {
                const ok = blk: {
                    for (storage.columns) |col| {
                        if (col.id == column.id) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };
                if (!ok) @panic("setRaw with non-matching column");
            }
            mem.copy(u8, storage.block[column.offset + (row_index * column.size) ..], component);
        }

        /// Swap-removes the specified row with the last row in the table.
        pub fn remove(storage: *Self, row_index: u32) void {
            if (storage.len > 1) {
                for (storage.columns) |column| {
                    const dstStart = column.offset + (column.size * row_index);
                    const dst = storage.block[dstStart .. dstStart + (column.size)];
                    const srcStart = column.offset + (column.size * (storage.len - 1));
                    const src = storage.block[srcStart .. srcStart + (column.size)];
                    std.mem.copy(u8, dst, src);
                }
            }
            storage.len -= 1;
        }

        /// Tells if this archetype has every one of the given components.
        pub fn hasComponents(storage: *Self, components: []const ColumnId) bool {
            for (components) |component_name| {
                if (!storage.hasComponent(component_name)) return false;
            }
            return true;
        }

        /// Tells if this archetype has a component with the specified name.
        pub fn hasComponent(storage: *Self, component: ColumnId) bool {
            for (storage.columns) |column| {
                if (column.id == component) return true;
            }
            return false;
        }

        pub fn copyRow(src: *Self, src_index: u32, dest: *Self, dest_index: u32) void {
            for (dest.columns) |column| {
                if (column.id == @enumToInt(ComponentTag.id)) continue;
                for (src.columns) |corresponding| {
                    if (column.id == corresponding.id) {
                        const old_value_raw = src.getRaw(src_index, column.id);
                        dest.setRaw(dest_index, column, old_value_raw) catch |err| {
                            dest.undoAppend();
                            return err;
                        };
                        break;
                    }
                }
            }
        }
    };
}

// fn calculateHash(names: []const []const u8) u64 {
//     var hash: u64 = 0;
//     for (names) |name| {
//         hash ^= std.hash_map.hashString(name);
//     }
//     return hash;
// }

// test "hash" {
//     var h1 = calculateHash(&.{ "id", "rotation", "position" });
//     var h2 = calculateHash(&.{ "position", "rotation", "id" });
//     std.debug.print("H: {} -> {}", .{ h1, h2 });
//     try std.testing.expect(h1 == h2);
// }

test "init" {
    std.debug.print("\n start init \n", .{});
    const Components = struct { id: EntityID };

    const Tags = std.meta.FieldEnum(Components);

    const Storage = ArchetypeStorage(u16, Tags);
    const Column = Storage.Column;

    const allocator = std.testing.allocator;
    const columns = try allocator.alloc(Column, 1);
    columns[0] = Column.init(@enumToInt(Tags.id), EntityID);
    var b = Storage.init(allocator, columns);

    const row = Components{ .id = 42 };

    // const MyType = struct {
    //     location: f32,
    //     rotation: f32,
    // };

    var row_index = try b.append(row);
    var res = b.getInto(row_index, Components);
    try std.testing.expect(res != null);

    defer b.deinit();
    //try std.testing.expect(b.len == 0);
}
