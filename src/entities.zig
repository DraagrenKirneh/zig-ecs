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

const ArchetypeId = u64;

const Column = @import("storage.zig").Column;

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

const ComponentId = ecs.ComponentId;

pub fn Entities(comptime TComponents: type) type {
    return struct {
        allocator: Allocator,

        /// generator / recycler of entityID's
        id_generator: ecs.IdentityGenerator = .{},

        /// A mapping of entity IDs (array indices) to where an entity's component values are actually
        /// stored.
        entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .{},

        /// A mapping of archetype hash to their storage.
        ///
        /// Database equivalent: table name -> tables representing entities.
        archetypes: std.AutoArrayHashMapUnmanaged(ArchetypeId, ArchetypeStorage) = .{},

        // @todo add back component indexes, maybe
        //indexes: ArchetypeIndex(Tag, TComponents),

        const Self = @This();

        pub const Tag: type = std.meta.FieldEnum(TComponents);
        pub const AnyComponent = reflection.ComponentUnion(TComponents);

        const ArchetypeStorage = ecs.ArchetypeStorage();
        const Resolver = ComponentId.Resolver(Tag);

        //@TODO traits validator
        //const Traits = @import("traits.zig").MyTraits(TComponents, Tag);

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

        pub fn Pair(comptime key_tag: Tag, comptime value_tag: Tag) type {
            return reflection.Pair(
                TypeFromTag(key_tag),
                TypeFromTag(value_tag),
                Tag,
                key_tag,
                value_tag,
            );
        }

        fn TypeFromTag(comptime tag: Tag) type {
            return std.meta.fieldInfo(TComponents, tag).type;
        }

        pub fn Wildcard(comptime key_tag: Tag) type {
            return struct {
                iterator: Iterator,

                const Result = struct {
                    key: Key,
                    value: AnyComponent,
                };

                pub const Key = TypeFromTag(key_tag);
                pub const wildcard_tag = key_tag;

                pub fn initIterator(storage: *const ArchetypeStorage, row_index: u32) @This() {
                    return .{ .iterator = .{ .storage = storage, .row_index = row_index } };
                }

                const Iterator = struct {
                    storage: *const ArchetypeStorage,
                    row_index: u32,

                    column_index: u32 = 0,

                    pub fn next(self: *Iterator) ?Result {
                        const columnCount = self.storage.columns.len;
                        while (self.column_index < columnCount) {
                            const old_index = self.column_index;
                            self.column_index += 1;

                            const column_id = self.storage.getColumnId(old_index);
                            // if column is pair and has key value of ...
                            if (column_id.pair == 1 and column_id.component_a == @enumToInt(key_tag)) {
                                inline for (std.meta.fields(Tag)) |f| {
                                    if (column_id.component_b == f.value) {
                                        const MyPair = Pair(key_tag, @intToEnum(Tag, f.value));
                                        const pair = self.storage.getByColumnIndex(
                                            self.row_index,
                                            self.column_index,
                                            MyPair,
                                        );
                                        return Result{
                                            .key = pair.key,
                                            .value = @unionInit(AnyComponent, f.name, pair.value),
                                        };
                                    }
                                }
                            }
                        }
                        return null;
                    }
                };
            };
        }

        fn by_alignment_name(context: void, lhs: Column, rhs: Column) bool {
            _ = context;
            if (lhs.alignment < rhs.alignment) return true;
            return lhs.id.value() < rhs.id.value();
        }

        fn extractComponentIds(comptime ValueT: type) []const ComponentId {
            return comptime blk: {
                const fields = std.meta.fields(ValueT);
                var identifers: [fields.len]ComponentId = undefined;
                inline for (fields, 0..) |f, i| {
                    identifers[i] = Resolver.fromField(f);
                }
                break :blk identifers[0..];
            };
        }

        pub fn TypedIter(comptime T: type) type {
            return struct {
                entities: *const Self,
                archetype_index: usize = 0,
                row_index: u32 = 0,

                const Iterator = @This();
                const component_identifiers = extractComponentIds(T);

                pub fn init(entities: *const Self) Iterator {
                    var iterator = Iterator{
                        .entities = entities,
                    };

                    return iterator;
                }

                pub fn next(iter: *Iterator) ?T {
                    const entities = iter.entities;
                    var archetype: *const ArchetypeStorage = &entities.archetypes.values()[iter.archetype_index];
                    while (!archetype.hasComponents(component_identifiers) or iter.row_index >= archetype.len) {
                        iter.archetype_index += 1;
                        iter.row_index = 0;
                        if (iter.archetype_index >= entities.archetypes.count()) {
                            return null;
                        }
                        archetype = &entities.archetypes.values()[iter.archetype_index];
                    }

                    var row_index = iter.row_index;
                    iter.row_index += 1;

                    var res = archetype.getInto(row_index, T, component_identifiers);

                    inline for (std.meta.fields(T)) |f| {
                        if (@typeInfo(f.type) == .Struct and @hasDecl(f.type, "wildcard_tag")) {
                            @field(res, f.name) = f.type.initIterator(archetype, iter.row_index);
                        }
                    }
                    return res;
                }
            };
        }

        pub fn getEntity(self: *const Self, comptime T: type, id: EntityID) ?T {
            if (self.entities.get(id)) |ptr| {
                const archetype = self.archetypeByID(id);
                const components = extractComponentIds(T);
                if (!archetype.hasComponents(components)) return null;
                return archetype.getInto(ptr.row_index, T);
            }
            return null;
        }

        pub fn getIterator(self: *Self, comptime T: type) TypedIter(T) {
            return TypedIter(T){
                .entities = self,
            };
        }

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                //.indexes = ArchetypeIndex(Tag, TComponents).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit(self.allocator);

            var iter = self.archetypes.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.archetypes.deinit(self.allocator);
            self.id_generator.list.deinit(self.allocator);
            //self.indexes.deinit();
        }

        /// Returns a new entity.
        pub fn new(self: *Self) !EntityID {
            return self.create(void, {});
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

                // fix me validate that we can do this;
                const column_fields = std.meta.fields(Row);
                const columns = try self.allocColumns(column_fields.len, hash);

                inline for (column_fields, 0..) |field, index| {
                    const componentId = Resolver.fromField(field);
                    columns[index] = Column.init(componentId, field.type);
                    // @INDEX
                    // try self.indexes.register(
                    //     field.type,
                    //     columnId,
                    //     @intCast(u16, archetype_entry.index),
                    // );
                }

                std.sort.sort(Column, columns, {}, by_alignment_name);
                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);
            }

            var current_archetype_storage = archetype_entry.value_ptr;

            var row = copyStructToStruct(Row, T, components);
            if (row.id == 0) {
                row.id = self.id_generator.generate();
            }

            const identifiers = extractComponentIds(Row);
            const row_index = try current_archetype_storage.append(Row, row, identifiers);
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
                const idComponent = ComponentId.initComponent(@enumToInt(Tag.id));
                const last_row_entity_id = archetype.get(archetype.len - 1, idComponent, EntityID).?;
                try self.putEntityPointer(last_row_entity_id, ptr);
            }

            // Perform a swap removal to remove our entity from the archetype table.
            archetype.remove(ptr.row_index);

            _ = self.entities.remove(entity);

            try self.id_generator.recycle(self.allocator, entity);
        }

        /// Returns the archetype storage for the given entity.
        inline fn archetypeByID(self: *const Self, entity: EntityID) *ArchetypeStorage {
            const ptr = self.entities.get(entity).?;
            return &self.archetypes.values()[ptr.archetype_index];
        }

        pub fn setPair(
            self: *Self,
            entity: EntityID,
            comptime key_tag: Tag,
            comptime value_tag: Tag,
            component: Pair(key_tag, value_tag),
        ) !void {
            const Component = Pair(key_tag, value_tag);
            const pairId = ComponentId.initPair(@enumToInt(key_tag), @enumToInt(value_tag));
            return self.privSetComponent(entity, pairId, Component, component);
        }

        /// Sets the named component to the specified value for the given entity,
        /// moving the entity from it's current archetype table to the new archetype
        /// table if required.
        pub fn setComponent(
            self: *Self,
            entity: EntityID,
            comptime tag: Tag,
            component: std.meta.fieldInfo(TComponents, tag).type,
        ) !void {
            const componentId = ComponentId.initComponent(@enumToInt(tag));
            return self.privSetComponent(entity, componentId, @TypeOf(component), component);
        }

        pub fn setAnyComponent(
            self: *Self,
            entity: EntityID,
            component: AnyComponent,
        ) !void {
            const activeTag = std.meta.activeTag(component);
            const componentId = ComponentId.initComponent(@enumToInt(activeTag));
            return switch (component) {
                else => |e| self.privSetComponent(entity, componentId, @TypeOf(e), e),
            };
        }

        pub fn getPair(
            self: *Self,
            entity: EntityID,
            comptime firstTag: Tag,
            comptime secondTag: Tag,
        ) ?Pair(firstTag, secondTag) {
            const Component = Pair(firstTag, secondTag);
            var archetype = self.archetypeByID(entity);
            const ptr = self.entities.get(entity).?;
            const pairId = ComponentId.initPair(@enumToInt(firstTag), @enumToInt(secondTag));
            return archetype.get(ptr.row_index, pairId, Component);
        }

        /// gets the named component of the given type (which must be correct, otherwise undefined
        /// behavior will occur). Returns null if the component does not exist on the entity.
        /// !! not valid as name is an enum tag now ^^
        pub fn getComponent(
            self: *Self,
            entity: EntityID,
            comptime tag: Tag,
        ) ?std.meta.fieldInfo(TComponents, tag).type {
            const Component = comptime std.meta.fieldInfo(TComponents, tag).type;
            const componentId = ComponentId.initComponent(@enumToInt(tag));

            const ptr = self.entities.get(entity).?;
            const archetype: *const ArchetypeStorage = self.archetypeByID(entity);
            return archetype.get(ptr.row_index, componentId, Component);
        }

        pub fn removePair(self: *Self, entity: EntityID, key_tag: Tag, value_tag: Tag) !void {
            const componentId = ComponentId.initPair(@enumToInt(key_tag), @enumToInt(value_tag));
            return self.privRemoveComponent(entity, componentId);
        }

        /// Removes the named component from the entity, or noop if it doesn't have such a component.
        pub fn removeComponent(
            self: *Self,
            entity: EntityID,
            tag: Tag,
        ) !void {
            const componentId = ComponentId.initComponent(@enumToInt(tag));
            return self.privRemoveComponent(entity, componentId);
        }

        fn privSetComponent(
            self: *Self,
            entity: EntityID,
            componentId: ComponentId,
            comptime Component: type,
            component: Component,
        ) !void {
            var archetype = self.archetypeByID(entity);

            // Determine the old hash for the archetype.
            const old_hash = archetype.hash;

            var have_already = archetype.hasComponent(componentId);

            const new_hash = if (have_already) old_hash else hashExisting(old_hash, componentId.value());

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
                columns[columns.len - 1] = Column.init(componentId, Component);
                std.sort.sort(Column, columns, {}, by_alignment_name);

                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);

                // for (columns) |column| {
                //     try self.indexes.append(column.id, @intCast(u16, archetype_entry.index));
                // }
            }

            // Either new storage (if the entity moved between storage tables due to having a new
            // component) or the prior storage (if the entity already had the component and it's value
            // is merely being updated.)
            //var current_archetype_storage = &archetype_entry.value_ptr;

            if (new_hash == old_hash) {
                // Update the value of the existing component of the entity.
                const ptr = self.entities.get(entity).?;
                archetype.set(ptr.row_index, componentId, Component, component);
                return;
            }

            // Copy to all component values for our entity from the old archetype storage (archetype)
            // to the new one (current_archetype_storage).
            const new_row = try archetype_entry.value_ptr.appendUndefined();
            const old_ptr = self.entities.get(entity).?;

            // Update the storage/columns for all of the existing components on the entity.
            const entityComponentid = ComponentId.initComponent(@enumToInt(Tag.id));
            archetype_entry.value_ptr.set(new_row, entityComponentid, EntityID, entity);
            archetype.copyRow(old_ptr.row_index, archetype_entry.value_ptr, new_row);

            // Update the storage/column for the new component.

            archetype_entry.value_ptr.set(new_row, componentId, Component, component);

            archetype.remove(old_ptr.row_index);

            // @fixme assert id == 0;
            const swapped_entity_id = archetype.get(old_ptr.row_index, .{}, EntityID).?;
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

        fn privRemoveComponent(
            self: *Self,
            entity: EntityID,
            componentId: ComponentId,
        ) !void {
            var archetype = self.archetypeByID(entity);
            if (!archetype.hasComponent(componentId)) return;

            // Determine the old hash for the archetype.
            const old_hash = archetype.hash;

            // Determine the new hash for the archetype with the component removed
            var hasher = Wyhash.init(0);
            for (archetype.columns) |column| {
                if (!column.id.equal(componentId)) hasher.update(std.mem.asBytes(&column.id.value()));
            }
            const new_hash: u64 = hasher.final();
            assert(new_hash != old_hash);

            // Find the archetype storage this entity will move to. Note that although an entity with
            // (A, B, C) components implies archetypes ((A), (A, B), (A, B, C)) exist there is no
            // guarantee that archetype (A, C) exists - and so removing a component sometimes does
            // require creating a new archetype table!
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);

            // getOrPut allocated, so the archetype we retrieved earlier may no longer be a valid
            // pointer. Refresh it now:
            // archetype = self.archetypeByID(entity);

            if (!archetype_entry.found_existing) {
                archetype = self.archetypeByID(entity);

                const columns = try self.allocColumns(archetype.columns.len - 1, new_hash);

                var i: usize = 0;
                for (archetype.columns) |column| {
                    if (column.id.equal(componentId)) continue;
                    columns[i] = column;
                    i += 1;
                }

                // for (columns) |column| {
                //     try self.indexes.append(column.id, @intCast(u16, archetype_entry.index));
                // }

                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);
            }

            var current_archetype_storage = archetype_entry.value_ptr;

            // Copy to all component values for our entity from the old archetype storage (archetype)
            // to the new one (current_archetype_storage).
            const new_row = try current_archetype_storage.appendUndefined();
            const old_ptr = self.entities.get(entity).?;

            // Update the storage/columns for all of the existing components on the entity that exist in
            // the new archetype table (i.e. excluding the component to remove.)

            const component_id = ComponentId.initComponent(@enumToInt(Tag.id));
            current_archetype_storage.set(new_row, component_id, EntityID, entity);
            archetype.copyRow(old_ptr.row_index, current_archetype_storage, new_row);

            archetype.remove(old_ptr.row_index);
            const swapped_entity_id = archetype.get(old_ptr.row_index, component_id, EntityID).?;
            // TODO: try is wrong here and below?
            // if we removed the last entry from archetype, then swapped_entity_id == entity
            // so the second entities.put will clobber this one

            try self.putEntityPointer(swapped_entity_id, old_ptr);
            try self.putEntityPointer(entity, .{
                .archetype_index = @intCast(u16, archetype_entry.index),
                .row_index = new_row,
            });
        }

        fn putEntityPointer(self: *Self, id: EntityID, ptr: Pointer) !void {
            return self.entities.put(self.allocator, id, ptr);
        }

        fn hashType(comptime T: type) u64 {
            var hasher = Wyhash.init(0);

            inline for (std.meta.fields(T)) |field| {
                const value = Resolver.fromField(field).value();
                hasher.update(std.mem.asBytes(&value));
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

    const ptA = ComponentId.initPair(@enumToInt(VoidPairA.key_tag), @enumToInt(VoidPairA.value_tag));
    const ptB = ComponentId.initPair(@enumToInt(VoidPairB.key_tag), @enumToInt(VoidPairB.value_tag));
    try std.testing.expect(!ptA.equal(ptB));
}

test "any component" {
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
    _ = Entry;

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    var entityId = try entities.new();

    try entities.setAnyComponent(entityId, .{ .position = 42 });

    const componentPosition = entities.getComponent(entityId, .position).?;
    try expectEqualOf(f32, 42, componentPosition);
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

    const value_result = entities.getComponent(entityId, .value).?;
    try expectEqualOf(i32, 5, value_result);

    const position_result = entities.getComponent(entityId, .position).?;
    try expectEqualOf(f32, 4, position_result);
}

test "wildcard iterator" {
    const allocator = std.testing.allocator;

    const Game = struct {
        id: ecs.EntityID,
        planet: void,
        value: i32,
        sun: void,
        moon: void,
    };

    const MyEntities = Entities(Game);

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    const entityId = try entities.new();

    try entities.setPair(entityId, .planet, .sun, .{});
    try entities.setPair(entityId, .planet, .value, .{ .value = 22 });
    const componentValue = entities.getPair(entityId, .planet, .value).?;
    //try expectEqualOf(f32, 10, componentValue.key);
    try expectEqualOf(i32, 22, componentValue.value);

    try entities.setPair(entityId, .planet, .moon, .{});

    const Wit = MyEntities.Wildcard(.planet);
    var it = Wit.initIterator(entities.archetypeByID(entityId), 0);

    const val = it.iterator.next().?;
    std.debug.print("\nres, val: {}\n", .{val.value});
    try std.testing.expect(val.value == .sun);
    //try std.debug.assert(val != null);
}

test "basic Pair" {
    const allocator = std.testing.allocator;

    const Game = struct {
        id: ecs.EntityID,
        position: f32,
        size: i32,
        sun: void,
    };

    const MyEntities = Entities(Game);

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    const entityId = try entities.new();

    try entities.setPair(entityId, .sun, .size, .{ .value = 44 });
    try entities.setPair(entityId, .sun, .position, .{ .value = 22 });

    const componentValue = entities.getPair(entityId, .sun, .size).?;
    try expectEqualOf(i32, 44, componentValue.value);

    const Query = struct {
        id: ecs.EntityID,
        pair_a: MyEntities.Pair(.sun, .position),
        pair_b: MyEntities.Pair(.sun, .size),
    };

    var it = entities.getIterator(Query);

    const result = it.next().?;

    try expectEqual(EntityID, entityId, result.id);

    try expectEqual(void, {}, result.pair_a.key);
    try expectEqual(f32, 22, result.pair_a.value);

    try expectEqual(void, {}, result.pair_b.key);
    try expectEqual(i32, 44, result.pair_b.value);

    try std.testing.expect(it.next() == null);
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
    try std.testing.expect(result == null);

    try entities.setPair(entity_id, .inventory, .cake, .{ .value = 999 });
    result = entities.getPair(entity_id, .inventory, .cake);
    try std.testing.expect(result.?.value == 999);

    const Query = struct {
        stuff: i32,
        planet_wildcard: MyEntities.Wildcard(.planet),
    };

    var iterator = entities.getIterator(Query);

    const query_result: ?Query = iterator.next();
    try std.testing.expect(query_result != null);
    var wildcard_value_it = query_result.?.planet_wildcard.iterator;

    var count: usize = 0;
    var bit_set: u4 = 0;
    while (wildcard_value_it.next()) |pair| {
        count += 1;
        const value: u4 = switch (pair.value) {
            .pluto => 0b1000,
            .mars => 0b0100,
            .sun => 0b0010,
            else => 0b0001,
        };
        bit_set = bit_set | value;
    }

    try expectEqual(u4, 0b1110, bit_set);
    try expectEqual(usize, 3, count);
    try std.testing.expect(iterator.next() == null);
}

test "ecc" {
    const Sub = struct {
        x: f32 = 0,
        y: f32 = 0,
    };

    const Game = struct {
        id: ecs.EntityID,
        location: f32,
        name: []const u8,
        rotation: u32,
        value: i32,
        ChildOf: void,
        Sun: void,
        Moon: void,
        sub: Sub,
    };
    const MyStorage = Entities(Game);
    const allocator = std.testing.allocator;
    const Entry = struct {
        rotation: u32,
    };

    const EntryWithId = struct { id: ecs.EntityID, location: f32 };

    var b = MyStorage.init(allocator);
    defer b.deinit();

    var e2 = try b.create(Entry, .{ .rotation = 75 });

    try expectEqualOf(u32, 75, b.getComponent(e2, .rotation).?);

    var e = try b.new();
    try b.setComponent(e, .rotation, 42);

    const Enemy = struct { location: f32, rotation: i32 };

    const Result = struct { rotation: *u32 };

    var iter = b.getIterator(Result);
    var val = b.getComponent(e, .rotation);
    try std.testing.expect(val != null);
    try std.testing.expect(val.? == 42);

    iter.next().?.rotation.* = 123;
    var val2 = b.getComponent(e2, .rotation).?;
    try std.testing.expectEqual(val2, 123);

    var entry = iter.next();
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.rotation.* == 42);

    try std.testing.expect(iter.next() == null);

    var e3 = try b.create(Enemy, .{ .location = 22, .rotation = 55 });
    _ = e3;
    try b.removeComponent(e, .rotation);
    val = b.getComponent(e, .rotation);
    try std.testing.expect(val == null);
    try b.remove(e);

    var exx = try b.create(EntryWithId, .{ .id = 777, .location = 25 });
    try expectEqualOf(ecs.EntityID, 777, exx);
}

fn expectEqualOf(comptime T: type, expected: T, actual: T) !void {
    return std.testing.expectEqual(expected, actual);
}

test "Pair Pair Pair" {
    const Game = struct {
        id: ecs.EntityID,
        location: f32,
        name: []const u8,
        rotation: u32,
        value: i32,
        ChildOf: void,
        Sun: void,
        Moon: void,
        _Pair: void,
    };
    const MyEntites = Entities(Game);
    const allocator = std.testing.allocator;

    const Entry = struct {
        rotation: u32,
    };

    _ = Entry;

    var entities = MyEntites.init(allocator);
    defer entities.deinit();
}
