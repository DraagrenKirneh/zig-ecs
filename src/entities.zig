const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const builtin = @import("builtin");
const reflection = @import("reflection.zig");
const ecs = @import("ecs.zig");
const autoHash = std.hash.autoHash;
const Wyhash = std.hash.Wyhash;

const assert = std.debug.assert;

const EntityID = ecs.EntityID;
//const ArchetypeStorage = storage.ArchetypeStorage;
const void_archetype_hash = ecs.void_archetype_hash;

//const typeId = ecs.typeId;

//const ComponentId = ecs.TypeId;

const ArchetypeId = u64;

// fixme u32
const ComponentId = u32;
pub fn PackedComponentId(comptime T: type) type {
    return packed struct {
        component_a: u14,
        component_b: u14 = 0,
        reserved: u2 = 0,
        pair: u1 = 0,
        wildcard: u1 = 0,

        const Self = @This();

        pub inline fn componentIdFromName(comptime name: []const u8) ComponentId {
            const tag = std.meta.stringToEnum(T, name).?;
            return componentId(tag);
        }

        pub inline fn componentIdFromNameXXZ(comptime tag: T, comptime name: []const u8) ComponentId {
            const component_tag = std.meta.stringToEnum(T, name).?;
            const self = Self{ .component_a = @enumToInt(tag), .component_b = @enumToInt(component_tag), .pair = 1 };

            return @bitCast(ComponentId, self);
            //return componentId(tag);
        }

        pub inline fn fromPairType(comptime Pair: type) ComponentId {
            return pairId(Pair.key_tag, Pair.value_tag);
        }

        pub inline fn fromWildcard(comptime Wildcard: type) ComponentId {
            var self = Self{ .component_a = @enumToInt(Wildcard.wildcard_key), .wildcard = 1 };
            return @bitCast(ComponentId, self);
        }

        pub inline fn getKeyPartXYZ(cid: ComponentId) ComponentId {
            const current = @bitCast(Self, cid);
            return @bitCast(ComponentId, Self{ .component_a = current.component_b });
        }

        // pub inline fn getKeyPartXYZ(cid: ComponentId) ComponentId {
        //     const current = @bitCast(Self, cid);
        //     return @bitCast(ComponentId, Self{ .component_a = current.component_a });
        // }

        pub inline fn getPairFromWildcard(cid: ComponentId, comptime tag: T) ComponentId {
            const current = @bitCast(Self, cid);
            current.wildcard = 0;
            current.pair = 1;
            current.component_a = @enumToInt(tag);
            return @bitCast(ComponentId, Self{ .component_a = current.component_a });
        }

        pub inline fn wildcardMask(comptime tag: T) ComponentId {
            var self = Self{ .component_a = @enumToInt(tag), .pair = 1 };
            return @bitCast(ComponentId, self);
        }

        pub inline fn valueTagFromId(cid: ComponentId) T {
            const current = @bitCast(Self, cid);
            return @intToEnum(T, current.component_b);
        }

        pub inline fn keyTagFromId(cid: ComponentId) T {
            const current = @bitCast(Self, cid);
            return @intToEnum(T, current.component_b);
        }

        pub inline fn pairToWildcard(cid: ComponentId) ComponentId {
            const current = @bitCast(Self, cid);
            const self = Self{ .component_a = current.component_a, .wildcard = 1 };
            return @bitCast(ComponentId, self);
        }

        pub inline fn fromType(comptime Type: type, comptime name: []const u8) ComponentId {
            if (@typeInfo(Type) != .Struct) return componentIdFromName(name);
            return if (@hasDecl(Type, "key_tag"))
                fromPairType(Type)
            else if (@hasDecl(T, "wildcard_key"))
                fromWildcard(T)
            else
                componentIdFromName(name);
        }

        pub inline fn componentId(tag: T) ComponentId {
            var self = Self{ .component_a = @enumToInt(tag) };
            return @bitCast(ComponentId, self);
        }

        pub inline fn pairId(key: T, value: T) ComponentId {
            var self = Self{ .component_a = @enumToInt(key), .component_b = @enumToInt(value), .pair = 1 };
            return @bitCast(ComponentId, self);
        }

        pub inline fn id(self: Self) ComponentId {
            return @bitCast(ComponentId, self);
        }
    };
}

const trait = std.meta.trait;

pub fn MyTraits(comptime Components: type, comptime Tag: type) type {
    return struct {
        pub fn isComponent(comptime field_type: type, comptime field_name: []const u8) bool {
            if (@hasField(Components, field_name)) {
                if (std.meta.stringToEnum(Tag, field_name)) |tag| {
                    return std.meta.FieldType(Components, tag) == field_type;
                }
            }
            return false;
        }

        const FieldType = enum { Component, Pair, Wildcard, Invalid };

        fn hasDecl(comptime name: []const u8) trait.TraitFn {
            const Closure = struct {
                pub fn trait(comptime T: type) bool {
                    const fields = switch (@typeInfo(T)) {
                        .Struct => |s| s.decls,
                        else => return false,
                    };

                    inline for (fields) |field| {
                        if (mem.eql(u8, field.name, name)) return true;
                    }

                    return false;
                }
            };
            return Closure.trait;
        }

        pub fn isPair(comptime T: type) bool {
            const traits = comptime trait.multiTrait(.{
                hasDecl("key_tag"),
                hasDecl("value_tag"),
                trait.hasField("key"),
                trait.hasField("value"),
            });

            return traits(T);
        }

        pub fn isValidRow(comptime T: type) bool {
            const fields = comptime std.meta.fields(T);
            inline for (fields) |field| {
                const isValidField = comptime isComponent(field.type, field.name) or isPair(field.type);
                comptime if (!isValidField) {
                    //@compileError("field not valid: " ++ field.name);
                    return false;
                };
            }
            return true;
        }
    };
}

fn copyStructToStruct(comptime Output: type, comptime Input: type, input: Input) Output {
    var output: Output = undefined;
    output.id = 0;
    if (Input == void) return output;
    const component_fields = @typeInfo(Input).Struct.fields;
    inline for (component_fields) |f| {
        if (@hasField(Output, f.name)) {
            @field(output, f.name) = @field(input, f.name);
        }
    }

    return output;
}

const TypeId = reflection.TypeId;

pub fn ArchetypeIndex(comptime Tag: type, comptime Field: type) type {
    return struct {
        const ComponentCount = std.meta.fields(Tag).len;
        const Set = std.AutoHashMapUnmanaged(u16, void);
        const Map = std.AutoHashMapUnmanaged(usize, Set);
        const WildcardMap = std.AutoArrayHashMapUnmanaged(usize, usize);
        const Packer = PackedComponentId(Field);

        allocator: Allocator,
        map: Map = .{},

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            var it = self.map.valueIterator();
            while (it.next()) |value_ptr| {
                value_ptr.deinit(self.allocator);
            }
            self.map.deinit(self.allocator);
        }

        fn addEntry(self: *Self, component_id: usize, storage_index: u16) !void {
            var entry = try self.map.getOrPut(self.allocator, component_id);
            if (!entry.found_existing) {
                entry.value_ptr.* = .{};
            }
            try entry.value_ptr.put(self.allocator, storage_index, {});
        }

        pub fn append(self: *Self, component_id: usize, storage_index: u16) !void {
            try self.addEntry(component_id, storage_index);
            if (component_id < ComponentCount) return;
            const wildcard_id = Packer.pairToWildcard(@intCast(u32, component_id));
            try self.addEntry(wildcard_id, storage_index);
        }

        pub fn register(self: *Self, comptime T: type, component_id: usize, storage_index: u16) !void {
            _ = T;
            return self.append(component_id, storage_index);
        }

        pub fn IndexIterator(comptime T: type) type {
            return struct {
                const fields = std.meta.fields(T);
                const identifiers = blk: {
                    var buf: [fields.len]ComponentId = undefined;
                    inline for (fields, 0..) |field, index| {
                        const value = Packer.fromType(field.type, field.name);
                        buf[index] = value;
                    }
                    break :blk buf;
                };
                indexes: *const Self,
                iterator: Self.Set.KeyIterator = undefined,

                const Iterator = @This();

                pub fn init(indexes: *const Self) Iterator {
                    const ix = fields.len - 1;
                    return .{
                        .indexes = indexes,
                        .iterator = indexes.getSetIterator(fields[ix].type, identifiers[ix]),
                    };
                }

                pub fn next(it: *Iterator) ?u16 {
                    loop: while (it.iterator.next()) |archetype| {
                        inline for (1..fields.len) |fIndex| {
                            const index = fields.len - fIndex - 1;
                            const id = identifiers[index];
                            if (!it.haveItem(id, archetype)) continue :loop;
                        }
                        return archetype;
                    }
                    return null;
                }
            };
        }
    };
}

pub fn Entities(comptime TComponents: type) type {
    return struct {
        allocator: Allocator,

        /// TODO!
        counter: EntityID = 1,

        /// A mapping of entity IDs (array indices) to where an entity's component values are actually
        /// stored.
        entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .{},

        /// A mapping of archetype hash to their storage.
        ///
        /// Database equivalent: table name -> tables representing entities.
        archetypes: std.AutoArrayHashMapUnmanaged(ArchetypeId, ArchetypeStorage) = .{},

        indexes: ArchetypeIndex(TagType, TComponents),

        const Self = @This();
        pub const TagType: type = std.meta.FieldEnum(TComponents);

        const ColumnIdType = usize;
        const ArchetypeStorage = ecs.ArchetypeStorage(ColumnIdType, TagType);
        const Column = ArchetypeStorage.Column;
        const ComponentIdValue = @enumToInt(TagType.id);
        const AnyComponent = reflection.ComponentUnion(TComponents);

        const Traits = MyTraits(TComponents, TagType);

        const componentCount = std.meta.fields(TComponents).len;
        pub const PackedColumnId = PackedComponentId(TagType);
        /// Points to where an entity is stored, specifically in which archetype table and in which row
        /// of that table. That is, the entity's component values are stored at:
        ///
        /// ```
        /// Entities.archetypes[ptr.archetype_index].rows[ptr.row_index]
        /// ```
        ///
        pub const Pointer = struct {
            archetype_index: u16,
            row_index: u32,
        };

        fn tagType(comptime tag: TagType) type {
            return std.meta.fieldInfo(TComponents, tag).type;
        }

        pub fn Pair(comptime First: TagType, comptime Second: TagType) type {
            const TF = tagType(First);
            const TS = tagType(Second);

            return reflection.Pair(TF, TS, TagType, First, Second);
        }

        fn WildcardValueIterator(comptime Key_tag: TagType) type {
            return struct {
                mask: u32,
                storage: *const ArchetypeStorage,
                row_index: usize,

                column_index: usize = 0,
                const Iterator = @This();

                pub fn init(storage: *const ArchetypeStorage, row: usize, mask: u32) Iterator {
                    return Iterator{ .storage = storage, .row_index = row, .mask = mask };
                }

                pub fn next(self: *Iterator) ?AnyComponent {
                    const columnCount = self.storage.columns.len;
                    while (self.column_index < columnCount) {
                        const old_index = self.column_index;
                        self.column_index += 1;

                        const column_id = self.storage.getColumnId(old_index);

                        const column_value_id = PackedColumnId.getKeyPartXYZ(@intCast(u32, column_id));
                        if (column_id & self.mask == self.mask) {
                            //var raw = self.storage.getKnownRaw(self.row_index, old_index);
                            inline for (std.meta.fields(AnyComponent)) |f| {
                                const myCid = PackedColumnId.componentIdFromName(f.name);
                                if (myCid == column_value_id) {
                                    if (f.type == void) return @unionInit(AnyComponent, f.name, {});
                                    const X = packed struct { key: tagType(Key_tag), value: f.type };
                                    const column = self.storage.columns[old_index];
                                    const columnValues = @ptrCast([*]X, @alignCast(@alignOf(X), &self.storage.block[column.offset]));
                                    return @unionInit(AnyComponent, f.name, columnValues[self.row_index].value);
                                }
                            }
                        }
                    }
                    return null;
                }
            };
        }

        pub fn Wildcard(comptime key_tag: TagType) type {
            return struct {
                const Key_type = tagType(key_tag);
                pub const wildcard_tag = key_tag;
                key: Key_type,
                value_iterator: WildcardValueIterator(key_tag),
            };
        }

        fn by_alignment_name(context: void, lhs: Column, rhs: Column) bool {
            _ = context;
            if (lhs.alignment < rhs.alignment) return true;
            return lhs.id < rhs.id;
        }

        pub fn extractComponentIds(comptime ValueT: type) []const usize {
            return blk: {
                const fields = std.meta.fields(ValueT);
                var tags: [fields.len]usize = undefined;
                inline for (fields, 0..) |f, i| {
                    tags[i] = comptime PackedColumnId.fromType(f.type, f.name);
                }
                break :blk tags[0..];
            };
        }

        pub fn TypedIter2(comptime T: type) type {
            return struct {
                entities: *const Self,
                archetype_index: usize = 0,
                row_index: u32 = 0,

                const Iterator = @This();
                const Components = extractComponentIds(T);

                pub fn init(entities: *const Self) Iterator {
                    var iterator = Iterator{
                        .entities = entities,
                    };

                    return iterator;
                }

                pub fn next(iter: *Iterator) ?T {
                    const entities = iter.entities;
                    // If the archetype table we're looking at does not contain the components we're
                    // querying for, keep searching through tables until we find one that does.
                    var archetype = entities.archetypes.entries.get(iter.archetype_index).value;
                    while (!hasComponents(archetype, Components) or iter.row_index >= archetype.len) {
                        iter.archetype_index += 1;
                        iter.row_index = 0;
                        if (iter.archetype_index >= entities.archetypes.count()) {
                            return null;
                        }
                        archetype = entities.archetypes.entries.get(iter.archetype_index).value;
                    }

                    var row_index = iter.row_index;
                    iter.row_index += 1;
                    return archetype.getInto(row_index, T);
                }
            };
        }

        pub fn TypedIter(comptime T: type) type {
            return struct {
                entities: *const Self,
                archetype_index: usize = 0,
                row_index: u32 = 0,

                const Iterator = @This();
                const Components = extractComponentIds(T);

                pub fn init(entities: *const Self) Iterator {
                    var iterator = Iterator{
                        .entities = entities,
                    };

                    return iterator;
                }

                pub fn next(iter: *Iterator) ?T {
                    const entities = iter.entities;
                    // If the archetype table we're looking at does not contain the components we're
                    // querying for, keep searching through tables until we find one that does.
                    var archetype = entities.archetypes.entries.get(iter.archetype_index).value;
                    while (!hasComponents(archetype, Components) or iter.row_index >= archetype.len) {
                        iter.archetype_index += 1;
                        iter.row_index = 0;
                        if (iter.archetype_index >= entities.archetypes.count()) {
                            return null;
                        }
                        archetype = entities.archetypes.entries.get(iter.archetype_index).value;
                    }

                    var row_index = iter.row_index;
                    iter.row_index += 1;
                    return archetype.getInto(row_index, T);
                }
            };
        }

        pub fn getEntity(self: *const Self, comptime T: type, id: EntityID) ?T {
            const optional_ptr = self.entities.get(id);
            if (optional_ptr) |ptr| {
                const archetype = self.archetypeByID(id);
                const components = reflection.extract(T, TagType);
                if (!archetype.hasComponents(components)) return null;
                return archetype.getInto(ptr.row_index, T);
            }
            return null;
        }

        // @FixMe naming
        fn hasComponents(storage: ArchetypeStorage, components: []const ColumnIdType) bool {
            var archetype = storage;
            if (components.len == 0) return false;
            for (components) |component| {
                //const myName = swapTag2(component);
                if (!archetype.hasComponent(component)) return false;
            }
            return true;
        }

        pub fn getIterator(self: *Self, comptime T: type) TypedIter(T) {
            return TypedIter(T){
                .entities = self,
            };
        }

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .indexes = ArchetypeIndex(TagType, TComponents).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit(self.allocator);

            var iter = self.archetypes.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.archetypes.deinit(self.allocator);
            self.indexes.deinit();
        }

        /// Returns a new entity.
        pub fn new(self: *Self) !EntityID {
            return self.create(void, {});
        }

        fn hashType(comptime T: type) u64 {
            var hasher = Wyhash.init(0);

            inline for (std.meta.fields(T)) |field| {
                const isNumber = comptime Traits.isComponent(field.type, field.name);
                const isPair = comptime Traits.isPair(field.type);
                const number =
                    if (isNumber) PackedColumnId.componentIdFromName(field.name) else if (isPair) PackedColumnId.fromPairType(field.type) else 0;
                //const number = reflection.getComponentId(TagType, field.type, field.name);
                hasher.update(std.mem.asBytes(&number));
            }
            return hasher.final();
        }

        fn hashExisting(current: u64, next: u64) u64 {
            return Wyhash.hash(current, std.mem.asBytes(&next));
        }

        fn allocColumns(self: *Self, count: usize, archetypeHash: u64) ![]Column {
            return self.allocator.alloc(Column, count) catch |err| {
                assert(self.archetypes.swapRemove(archetypeHash));
                return err;
            };
        }

        pub fn create(self: *Self, comptime T: type, components: T) !EntityID {
            const Row = reflection.StructWrapperWithId(EntityID, T);
            // comptime if (!Traits.isValidRow(Row)) {
            //     std.debug.assert(false);
            //     //@compileError("nop");
            // };

            const hash = comptime hashType(Row);
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, hash);

            if (!archetype_entry.found_existing) {
                const column_fields = std.meta.fields(Row);
                const columns = try self.allocColumns(column_fields.len, hash);

                inline for (column_fields, 0..) |field, index| {
                    const columnId = PackedColumnId.fromType(field.type, field.name);
                    columns[index] = Column.init(columnId, field.type);
                    try self.indexes.register(
                        field.type,
                        columnId,
                        @intCast(u16, archetype_entry.index),
                    );
                }

                std.sort.sort(Column, columns, {}, by_alignment_name);
                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);
            }

            var current_archetype_storage = archetype_entry.value_ptr;

            var row = copyStructToStruct(Row, T, components);
            if (row.id == 0) {
                row.id = self.counter;
                self.counter += 1;
            }

            const row_index = try current_archetype_storage.append(row);
            const entity_pointer = Pointer{
                .archetype_index = @intCast(u16, archetype_entry.index),
                .row_index = row_index,
            };

            self.putEntityPointer(row.id, entity_pointer) catch |err| {
                current_archetype_storage.undoAppend();
                return err;
            };

            return row.id;
        }

        /// Removes an entity.
        pub fn remove(self: *Self, entity: EntityID) !void {
            var archetype = self.archetypeByID(entity);
            const ptr = self.entities.get(entity).?;

            // A swap removal will be performed, update the entity stored in the last row of the
            // archetype table to point to the row the entity we are removing is currently located.
            if (archetype.len > 1) {
                const last_row_entity_id = archetype.get(archetype.len - 1, ComponentIdValue, EntityID).?;
                try self.putEntityPointer(last_row_entity_id, ptr);
            }

            // Perform a swap removal to remove our entity from the archetype table.
            archetype.remove(ptr.row_index);

            _ = self.entities.remove(entity);
        }

        /// Returns the archetype storage for the given entity.
        pub inline fn archetypeByID(self: *const Self, entity: EntityID) *ArchetypeStorage {
            const ptr = self.entities.get(entity).?;
            return &self.archetypes.values()[ptr.archetype_index];
        }

        pub fn setPair(
            self: *Self,
            entity: EntityID,
            comptime firstTag: TagType,
            comptime secondTag: TagType,
            component: Pair(firstTag, secondTag),
        ) !void {
            const Component = Pair(firstTag, secondTag);
            std.debug.print("\nSet Pair: {s}, {d} xyz\n", .{ @typeName(Component), @sizeOf(Component) });
            const pairId = PackedColumnId.pairId(firstTag, secondTag);
            //const pairId: usize = reflection.componentPairId(TagType, Component);
            return self.privSetComponent(entity, pairId, Component, component);
        }

        /// Sets the named component to the specified value for the given entity,
        /// moving the entity from it's current archetype table to the new archetype
        /// table if required.
        pub fn setComponent(
            self: *Self,
            entity: EntityID,
            comptime tag: TagType,
            component: std.meta.fieldInfo(TComponents, tag).type,
        ) !void {
            const columnId = PackedColumnId.componentId(tag);
            return self.privSetComponent(entity, columnId, @TypeOf(component), component);
        }

        fn privSetComponent(
            self: *Self,
            entity: EntityID,
            columnId: ColumnIdType,
            comptime Component: type,
            component: Component,
        ) !void {
            var archetype = self.archetypeByID(entity);

            // Determine the old hash for the archetype.
            const old_hash = archetype.hash;

            var have_already = archetype.hasComponent(columnId);

            std.debug.print("\n\n\n --------- \n have {} | {s} -- \n aa: {b} \n", .{ have_already, @typeName(Component), columnId });

            const new_hash = if (have_already) old_hash else hashExisting(old_hash, columnId);
            std.debug.print("\n:H {} | {} == {} -- \n\n", .{
                old_hash == new_hash,
                old_hash,
                new_hash,
            });
            // Find the archetype storage for this entity. Could be a new archetype storage table (if a
            // new component was added), or the same archetype storage table (if just updating the
            // value of a component.)
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);
            archetype = self.archetypeByID(entity);
            if (!archetype_entry.found_existing) {
                // getOrPut allocated, so the archetype we retrieved earlier may no longer be a valid
                // pointer. Refresh it now:

                const columns = try self.allocColumns(archetype.columns.len + 1, new_hash);
                mem.copy(Column, columns, archetype.columns);
                columns[columns.len - 1] = Column.init(columnId, Component);
                std.sort.sort(Column, columns, {}, by_alignment_name);

                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);

                for (columns) |column| {
                    try self.indexes.append(column.id, @intCast(u16, archetype_entry.index));
                }
            }

            // Either new storage (if the entity moved between storage tables due to having a new
            // component) or the prior storage (if the entity already had the component and it's value
            // is merely being updated.)
            //var current_archetype_storage = &archetype_entry.value_ptr;

            if (new_hash == old_hash) {
                // Update the value of the existing component of the entity.
                std.debug.print("\n About to set: {d} \n", .{@sizeOf(Component)});
                const ptr = self.entities.get(entity).?;
                archetype.set(ptr.row_index, columnId, Component, component);
                return;
            }

            // Copy to all component values for our entity from the old archetype storage (archetype)
            // to the new one (current_archetype_storage).
            const new_row = try archetype_entry.value_ptr.appendUndefined();
            const old_ptr = self.entities.get(entity).?;

            // Update the storage/columns for all of the existing components on the entity.
            archetype_entry.value_ptr.set(new_row, ComponentIdValue, EntityID, entity);
            archetype.copyRow(old_ptr.row_index, archetype_entry.value_ptr, new_row);

            // Update the storage/column for the new component.

            archetype_entry.value_ptr.set(new_row, columnId, Component, component);

            archetype.remove(old_ptr.row_index);
            const swapped_entity_id = archetype.get(old_ptr.row_index, ComponentIdValue, EntityID).?;
            // TODO: try is wrong here and below?
            // if we removed the last entry from archetype, then swapped_entity_id == entity
            // so the second entities.put will clobber this one
            try self.putEntityPointer(swapped_entity_id, old_ptr);
            try self.putEntityPointer(entity, .{
                .archetype_index = @intCast(u16, archetype_entry.index),
                .row_index = new_row,
            });

            return;
        }

        pub fn getPair(self: *Self, entity: EntityID, comptime firstTag: TagType, comptime secondTag: TagType) ?Pair(firstTag, secondTag) {
            const Component = Pair(firstTag, secondTag);
            var archetype = self.archetypeByID(entity);
            const ptr = self.entities.get(entity).?;
            const pairId = PackedColumnId.fromPairType(Component);
            return archetype.get(ptr.row_index, pairId, Component);
        }

        /// gets the named component of the given type (which must be correct, otherwise undefined
        /// behavior will occur). Returns null if the component does not exist on the entity.
        /// !! not valid as name is an enum tag now ^^
        pub fn getComponent(
            self: *Self,
            entity: EntityID,
            comptime tag: TagType,
        ) ?std.meta.fieldInfo(TComponents, tag).type {
            const Component = comptime std.meta.fieldInfo(TComponents, tag).type;
            var archetype = self.archetypeByID(entity);

            const ptr = self.entities.get(entity).?;
            return archetype.get(ptr.row_index, @enumToInt(tag), Component);
        }

        fn privRemoveComponent(
            self: *Self,
            entity: EntityID,
            columnId: ColumnIdType,
        ) !void {
            var archetype = self.archetypeByID(entity);
            if (!archetype.hasComponent(columnId)) return;

            // Determine the old hash for the archetype.
            const old_hash = archetype.hash;

            // Determine the new hash for the archetype with the component removed
            var hasher = Wyhash.init(0);
            for (archetype.columns) |column| {
                if (column.id != columnId) hasher.update(std.mem.asBytes(&column.id));
            }
            var new_hash: u64 = hasher.final();
            assert(new_hash != old_hash);

            // Find the archetype storage this entity will move to. Note that although an entity with
            // (A, B, C) components implies archetypes ((A), (A, B), (A, B, C)) exist there is no
            // guarantee that archetype (A, C) exists - and so removing a component sometimes does
            // require creating a new archetype table!
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);

            // getOrPut allocated, so the archetype we retrieved earlier may no longer be a valid
            // pointer. Refresh it now:
            //archetype = self.archetypeByID(entity);

            if (!archetype_entry.found_existing) {
                archetype = self.archetypeByID(entity);

                const columns = try self.allocColumns(archetype.columns.len - 1, new_hash);

                var i: usize = 0;
                for (archetype.columns) |column| {
                    if (column.id == columnId) continue;
                    columns[i] = column;
                    i += 1;
                }

                for (columns) |column| {
                    try self.indexes.append(column.id, @intCast(u16, archetype_entry.index));
                }

                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);
            }

            var current_archetype_storage = archetype_entry.value_ptr;

            // Copy to all component values for our entity from the old archetype storage (archetype)
            // to the new one (current_archetype_storage).
            const new_row = try current_archetype_storage.appendUndefined();
            const old_ptr = self.entities.get(entity).?;

            // Update the storage/columns for all of the existing components on the entity that exist in
            // the new archetype table (i.e. excluding the component to remove.)
            current_archetype_storage.set(new_row, ComponentIdValue, entity);
            archetype.copyRow(old_ptr.row_index, current_archetype_storage, new_row);

            archetype.remove(old_ptr.row_index);
            const swapped_entity_id = archetype.get(old_ptr.row_index, ComponentIdValue, EntityID).?;
            // TODO: try is wrong here and below?
            // if we removed the last entry from archetype, then swapped_entity_id == entity
            // so the second entities.put will clobber this one

            try self.putEntityPointer(swapped_entity_id, old_ptr);
            try self.putEntityPointer(entity, .{
                .archetype_index = @intCast(u16, archetype_entry.index),
                .row_index = new_row,
            });
        }

        /// Removes the named component from the entity, or noop if it doesn't have such a component.
        pub fn removeComponent(
            self: *Self,
            entity: EntityID,
            comptime tag: TagType,
        ) !void {
            return self.privRemoveComponent(entity, @enumToInt(tag));
        }

        fn putEntityPointer(self: *Self, id: EntityID, ptr: Pointer) !void {
            return self.entities.put(self.allocator, id, ptr);
        }

        // TODO: iteration over all entities
        // TODO: iteration over all entities with components (U, V, ...)
        // TODO: iteration over all entities with type T
        // TODO: iteration over all entities with type T and components (U, V, ...)

        // TODO: "indexes" - a few ideas we could express:
        //
        // * Graph relations index: e.g. parent-child entity relations for a DOM / UI / scene graph.
        // * Spatial index: "give me all entities within 5 units distance from (x, y, z)"
        // * Generic index: "give me all entities where arbitraryFunction(e) returns true"
        //

        // TODO: ability to remove archetype entirely, deleting all entities in it
        // TODO: ability to remove archetypes with no entities (garbage collection)
    };
}

test "Pair type id" {
    const Game = struct {
        id: ecs.EntityID,
        position: f32,
        speed: f32,
        value: i32,
        sun: void,
        moon: void,
    };

    const MyEntities = Entities(Game);

    const VoidPairA = MyEntities.Pair(.sun, .moon);
    const VoidPairB = MyEntities.Pair(.moon, .sun);

    try std.testing.expect(reflection.typeIdValue(VoidPairA) != reflection.typeIdValue(VoidPairB));
}

test "basic" {
    const allocator = std.testing.allocator;

    const Game = struct {
        id: ecs.EntityID,
        position: f32,
        value: i32,
    };

    const MyEntities = Entities(Game);

    const Entry = struct {
        position: f32,
        value: i32,
    };

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    var entityId = try entities.create(Entry, .{ .position = 4, .value = 5 });

    const componentValue = entities.getComponent(entityId, .value).?;
    try expectEqualOf(i32, 5, componentValue);
}

test "basic Pair" {
    // const allocator = std.testing.allocator;

    // const Game = struct {
    //     id: ecs.EntityID,
    //     position: f32,
    //     value: i32,
    //     sun: void,
    // };

    // const MyEntities = Entities(Game);

    // var entities = MyEntities.init(allocator);
    // defer entities.deinit();

    // const entityId = try entities.new();

    // try entities.setPair(entityId, .position, .value, .{ .key = 10, .value = 22 });
    // const componentValue = entities.getPair(entityId, .position, .value).?;
    // try expectEqualOf(f32, 10, componentValue.key);
    // try expectEqualOf(i32, 22, componentValue.value);

    // try entities.setPair(entityId, .sun, .value, .{ .value = 22 });

    // const Wit = MyEntities.WildcardValueIterator(.sun);
    // const mask = MyEntities.PackedColumnId.wildcardMask(.sun);
    // var it = Wit.init(entities.archetypeByID(entityId), 0, mask);

    // const val = it.next().?;
    // std.debug.print("\nres, val: {}\n", .{val.value});
    // try std.testing.expect(val.value == 22);
    //_ = val;
    //switch (val) {}
    //try std.debug.assert(val != null);
    // const MyEntry = struct {
    //     id: ecs.EntityID,
    //     pair_a: MyEntities.Pair(.sun, .position),
    //     pair_b: MyEntities.Pair(.sun, .value),
    //     wild_c: MyEntities.Wildcard(.sun),
    // };

    // const ai = ArchetypeIndexes(MyEntities.TagType);
    // var aii = ai.init(allocator);

    // const Iter = ai.IndexIterator(MyEntry);

    // var it = Iter.init(&aii);
    // _ = it;
    //try it.next();
}

fn expectEqual(comptime T: type, expected: T, actual: T) !void {
    return std.testing.expectEqual(expected, actual);
}

test "pair n wildcard" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: EntityID,
        planet: void,
        sun: void,
        mars: void,
        pluto: void,
        cake: u32,
        inventory: void,
        stuff: i32,
    };

    const MyEntities = Entities(Components);

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    const EntityTemplate = struct {
        planet_sun: MyEntities.Pair(.planet, .sun) = .{},
        planet_mars: MyEntities.Pair(.planet, .mars) = .{},
        stuff: usize,
    };

    const entity_id = try entities.create(EntityTemplate, .{ .stuff = 42 });
    try entities.setPair(entity_id, .planet, .pluto, .{});
    try entities.setComponent(entity_id, .stuff, 45);

    var result = entities.getPair(entity_id, .inventory, .cake);
    try std.testing.expect(result.?.value == 0);

    try entities.setPair(entity_id, .inventory, .cake, .{ .value = 999 });

    result = entities.getPair(entity_id, .inventory, .cake);
    try std.testing.expect(result.?.value == 999);

    const Query = struct {
        stuff: i32,
        planet_wildcard: MyEntities.Wildcard(.planet),
    };

    var iterator = entities.getIterator(Query);

    const query_result: Query = iterator.next().?;

    //try expectEqual(type, void, query_result.planet_wildcard.key);

    var count: usize = 0;
    var value_it = query_result.planet_wildcard.value_iterator;
    while (value_it.next()) |value| {
        count += 1;
        const isOkValue = switch (value) {
            .pluto => true,
            .mars => true,
            .sun => true,
            else => false,
        };
        try std.testing.expect(isOkValue);
    }

    try expectEqual(usize, 3, count);
    try std.testing.expect(iterator.next() == null);
}

// test "ecc" {
//     const Sub = struct {
//         x: f32 = 0,
//         y: f32 = 0,
//     };

//     const Game = struct {
//         id: ecs.EntityID,
//         location: f32,
//         name: []const u8,
//         rotation: u32,
//         value: i32,
//         ChildOf: void,
//         Sun: void,
//         Moon: void,
//         sub: Sub,
//     };
//     const MyStorage = Entities(Game);
//     const allocator = std.testing.allocator;
//     const Entry = struct {
//         rotation: u32,
//     };

//     const EntryWithId = struct { id: ecs.EntityID, location: f32 };

//     var b = MyStorage.init(allocator);
//     defer b.deinit();

//     var e2 = try b.create(Entry, .{ .rotation = 75 });

//     try expectEqualOf(u32, 75, b.getComponent(e2, .rotation).?);

//     var e = try b.new();
//     try b.setComponent(e, .rotation, 42);

//     const Enemy = struct { location: f32, rotation: i32 };

//     const Result = struct { rotation: *u32 };
//     std.debug.print("e2 id: {} -> {}\n", .{ e2, e });

//     var iter = b.getIterator(Result);
//     var val = b.getComponent(e, .rotation);
//     try std.testing.expect(val != null);
//     try std.testing.expect(val.? == 42);

//     iter.next().?.rotation.* = 123;
//     var val2 = b.getComponent(e2, .rotation).?;
//     try std.testing.expectEqual(val2, 123);

//     var entry = iter.next();
//     try std.testing.expect(entry != null);
//     try std.testing.expect(entry.?.rotation.* == 42);

//     try std.testing.expect(iter.next() == null);

//     var e3 = try b.create(Enemy, .{ .location = 22, .rotation = 55 });
//     _ = e3;
//     try b.removeComponent(e, .rotation);
//     val = b.getComponent(e, .rotation);
//     try std.testing.expect(val == null);
//     try b.remove(e);

//     var exx = try b.create(EntryWithId, .{ .id = 777, .location = 25 });
//     try expectEqualOf(ecs.EntityID, 777, exx);
// }

fn expectEqualOf(comptime T: type, expected: T, actual: T) !void {
    return std.testing.expectEqual(expected, actual);
}

// test "Pair Pair Pair" {
//     const Game = struct {
//         id: ecs.EntityID,
//         location: f32,
//         name: []const u8,
//         rotation: u32,
//         value: i32,
//         ChildOf: void,
//         Sun: void,
//         Moon: void,
//         _Pair: void,
//     };
//     const MyEntites = Entities(Game);
//     const allocator = std.testing.allocator;

//     const Entry = struct {
//         rotation: u32,
//     };

//     _ = Entry;

//     var entities = MyEntites.init(allocator);
//     defer entities.deinit();
// }

// pub fn Iter(comptime components: []const TagType) type {

//     return struct {
//         entities: *Self,
//         archetype_index: usize = 0,
//         row_index: u32 = 0,

//         const Iterator = @This();

//         pub const Entry = struct {
//             entity: EntityID,
//             entities: *Self,

//             pub fn get(e: Entry, comptime T: type) ?T {
//                 var et = e.entities;
//                 const ptr = et.entities.get(e.entity).?;
//                 var archetype = et.archetypeByID(e.entity);
//                 return archetype.getInto(ptr.row_index, T);
//             }
//         };

//         pub fn next(iter: *Iterator) ?Entry {
//             const entities = iter.entities;
//             // If the archetype table we're looking at does not contain the components we're
//             // querying for, keep searching through tables until we find one that does.
//             var archetype = entities.archetypes.entries.get(iter.archetype_index).value;
//             while (!hasComponents(archetype, components) or iter.row_index >= archetype.len) {
//                 iter.archetype_index += 1;
//                 iter.row_index = 0;
//                 if (iter.archetype_index >= entities.archetypes.count()) {
//                     return null;
//                 }
//                 archetype = entities.archetypes.entries.get(iter.archetype_index).value;
//             }

//             const row_entity_id = archetype.get(iter.row_index, .id, EntityID).?;
//             iter.row_index += 1;
//             return Entry{ .entity = row_entity_id, .entities = iter.entities };
//         }
//     };
// }
