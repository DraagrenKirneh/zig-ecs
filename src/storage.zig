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

const ComponentId: type = ecs.ComponentId;

pub const Column = struct {
    id: ComponentId,
    size: u32,
    alignment: u16,
    offset: usize,

    const Self = @This();

    pub fn init(id: ComponentId, comptime component: type) Self {
        return .{
            .id = id,
            .size = @sizeOf(component),
            .alignment = if (@sizeOf(component) == 0) 1 else @alignOf(component),
            .offset = undefined,
        };
    }
};

/// Represents a single archetype, that is, entities which have the same exact set of component
/// types. When a component is added or removed from an entity, it's archetype changes.
///
/// Database equivalent: a table where rows are entities and columns are components (dense storage).
pub fn ArchetypeStorage() type {
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

        /// Calculates the storage.hash value. This is a hash of all the component names, and can
        /// effectively be used to uniquely identify this table within the database.
        pub fn calculateHash(storage: *Self) void {
            storage.hash = calculateHashInner(storage.columns);
        }

        fn calculateHashInner(columns: []const Column) u64 {
            var hasher = Wyhash.init(0);
            for (columns) |column| {
                hasher.update(std.mem.asBytes(&column.id.value()));
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

        /// appends a new row to this table, with all undefined values.
        pub fn appendUndefined(storage: *Self) !u32 {
            try storage.ensureUnusedCapacity(1);
            assert(storage.len < storage.capacity);
            const row_index = storage.len;
            storage.len += 1;
            return row_index;
        }

        pub fn append(storage: *Self, comptime Row: type, row: Row, identifiers: []const ComponentId) !u32 {
            var row_index = try storage.appendUndefined();
            storage.setRow(
                row_index,
                Row,
                row,
                identifiers,
            );
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
        pub fn setRow(storage: *Self, row_index: u32, comptime Row: type, row: Row, componentIds: []const ComponentId) void {
            inline for (std.meta.fields(Row), componentIds) |field, componentId| {
                const ColumnType = field.type;
                if (@sizeOf(ColumnType) == 0) continue;

                loop: for (storage.columns) |column| {
                    if (!column.id.equal(componentId)) continue :loop;
                    const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                    columnValues[row_index] = @field(row, field.name);
                }
            }
        }

        /// Sets the value of the named components (columns) for the given row in the table.
        pub fn set(storage: *Self, row_index: u32, id: ComponentId, comptime T: type, component: T) void {
            const ColumnType = @TypeOf(component);
            if (@sizeOf(T) == 0) {
                //std.debug.print("void type", .{});
                return;
            }
            for (storage.columns) |column| {
                if (!column.id.equal(id)) continue;

                const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                columnValues[row_index] = component;
                return;
            }
            @panic("no such component");
        }

        pub fn get(storage: *const Self, row_index: u32, id: ComponentId, comptime ColumnType: type) ?ColumnType {
            for (storage.columns) |column| {
                if (!column.id.equal(id)) continue;
                if (@sizeOf(ColumnType) == 0) return {};

                const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                return columnValues[row_index];
            }
            return null;
        }

        pub fn getByColumnIndex(storage: *const Self, row_index: u32, column_index: u32, comptime ColumnType: type) ColumnType {
            if (@sizeOf(ColumnType) == 0) return ColumnType{};
            const column = storage.columns[column_index];
            const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
            return columnValues[row_index];
        }

        pub fn getInto(storage: *const Self, row_index: u32, comptime TValue: type, comptime componentIds: []const ComponentId) ?TValue {
            var data: TValue = undefined;
            inline for (std.meta.fields(TValue), componentIds) |field, componentId| {
                if (@sizeOf(field.type) == 0) continue;
                const f_info = @typeInfo(field.type);
                const isPointer = f_info == .Pointer;
                const ColumnType = if (!isPointer) field.type else f_info.Pointer.child;

                for (storage.columns) |column| {
                    if (column.id.equal(componentId)) {
                        const columnValues = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), &storage.block[column.offset]));
                        @field(data, field.name) = if (isPointer) &columnValues[row_index] else columnValues[row_index];
                    }
                }
            }
            return data;
        }

        pub fn getColumnId(storage: *const Self, column_index: usize) ComponentId {
            return storage.columns[column_index].id;
        }

        pub fn getRaw(storage: *Self, row_index: u32, id: ComponentId) []u8 {
            for (storage.columns) |column| {
                if (!column.id.equal(id)) continue;
                const start = column.offset + (column.size * row_index);
                return storage.block[start .. start + (column.size)];
            }
            @panic("no such component");
        }

        pub fn setRaw(storage: *Self, row_index: u32, column: Column, component: []u8) !void {
            if (is_debug) {
                const ok = blk: {
                    for (storage.columns) |col| {
                        if (col.id.equal(column.id)) {
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
        pub fn hasComponents(storage: *const Self, components: []const ComponentId) bool {
            for (components) |component_name| {
                if (!storage.hasComponent(component_name)) return false;
            }
            return true;
        }

        /// Tells if this archetype has a component with the specified name.
        pub fn hasComponent(storage: *const Self, component: ComponentId) bool {
            for (storage.columns) |column| {
                if (component.equal(column.id)) return true;
                if (component.isWildcardOf(column.id)) return true;
            }
            return false;
        }

        pub fn copyRow(src: *Self, src_index: u32, dest: *Self, dest_index: u32) void {
            for (dest.columns) |column| {
                if (column.id.isEntityId()) continue;
                for (src.columns) |corresponding| {
                    if (column.id.equal(corresponding.id)) {
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

    const Storage = ArchetypeStorage();

    //const Resolver = ecs.ComponentId.Resolver(Tags);
    //const Column = Storage.Column;

    const allocator = std.testing.allocator;
    const columns = try allocator.alloc(Column, 1);
    const componentId = ComponentId.initComponent(@enumToInt(Tags.id));
    columns[0] = Column.init(componentId, EntityID);
    var b = Storage.init(allocator, columns);

    const row = Components{ .id = 42 };

    // const MyType = struct {
    //     location: f32,
    //     rotation: f32,
    // };

    var row_index = try b.append(
        Components,
        row,
        &[_]ComponentId{ComponentId.initComponent(0)},
    );
    var res = b.getInto(row_index, Components, &[_]ComponentId{ComponentId.initComponent(0)});
    try std.testing.expect(res != null);

    defer b.deinit();
    //try std.testing.expect(b.len == 0);
}
