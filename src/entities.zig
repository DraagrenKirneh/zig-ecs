const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const builtin = @import("builtin");
const reflection = @import("reflection.zig");
const ecs = @import("ecs.zig");

const assert = std.debug.assert;

const EntityID = ecs.EntityID;
//const ArchetypeStorage = storage.ArchetypeStorage;
const void_archetype_hash = ecs.void_archetype_hash;

const typeId = ecs.typeId;

pub fn Entities(comptime TComponents: type) type {
    return struct {
        allocator: Allocator,

        /// TODO!
        counter: EntityID = 0,

        /// A mapping of entity IDs (array indices) to where an entity's component values are actually
        /// stored.
        entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .{},

        /// A mapping of archetype hash to their storage.
        ///
        /// Database equivalent: table name -> tables representing entities.
        archetypes: std.AutoArrayHashMapUnmanaged(u64, ArchetypeStorage) = .{},

        const Self = @This();
        pub const TagType: type = std.meta.FieldEnum(TComponents);
        const ArchetypeStorage = ecs.ArchetypeStorage(TagType);
        const Column = ArchetypeStorage.Column;
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

        fn by_alignment_name(context: void, lhs: Column, rhs: Column) bool {
          _ = context;
          if (lhs.alignment < rhs.alignment) return true;
          return @enumToInt(lhs.name) < @enumToInt(rhs.name);
        }

        pub fn TypedIter(comptime T: type) type {
          const components = reflection.extract(T, TagType);
          return struct {
                entities: *const Self,
                archetype_index: usize = 0,
                row_index: u32 = 0,

                const Iterator = @This();              

                pub fn init(entities: *const Self) Iterator {
                  return .{
                    .entities = entities,
                  };
                }

                pub fn next(iter: *Iterator) ?T {                    
                    const entities = iter.entities;                    
                    // If the archetype table we're looking at does not contain the components we're
                    // querying for, keep searching through tables until we find one that does.
                    var archetype = entities.archetypes.entries.get(iter.archetype_index).value;
                    while (!hasComponents(archetype, components) or iter.row_index >= archetype.len) {                        
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
            if (optional_ptr) | ptr | {
                const archetype = self.archetypeByID(id);
                const components = reflection.extract(T, TagType);
                if (!archetype.hasComponents(components)) return null;
                return archetype.getInto(ptr.row_index, T);
            }
            return null;
        }

        fn hasComponents(storage: ArchetypeStorage, comptime components: []const TagType) bool {
            var archetype = storage;
            if (components.len == 0) return false;
            inline for (components) |component| {
                if (!archetype.hasComponent(component)) return false;
            }
            return true;
        }

        pub fn getIterator(self: *Self, comptime T: type) TypedIter(T) {
            return TypedIter(T){
                .entities = self,
            };
        }

        pub fn init(allocator: Allocator) !Self {
            var self = Self{ .allocator = allocator };

            const columns = try allocator.alloc(Column, 1);
            columns[0] = Column.init(.id, EntityID);

            try self.archetypes.put(allocator, void_archetype_hash, ArchetypeStorage{
                .allocator = allocator,
                .len = 0,
                .capacity = 0,
                .columns = columns,
                .block = undefined,
                .hash = void_archetype_hash,
            });

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit(self.allocator);

            var iter = self.archetypes.iterator();
            while (iter.next()) |entry| {
                // @Segfault fixme
                //if (entry.value_ptr.hash != void_archetype_hash) {
                  self.allocator.free(entry.value_ptr.block);
                //}                
                entry.value_ptr.deinit();
            }
            self.archetypes.deinit(self.allocator);
        }

        /// Returns a new entity.
        pub fn new(self: *Self) !EntityID {
            const new_id = self.counter;
            self.counter += 1;

            var void_archetype = self.archetypes.getPtr(void_archetype_hash).?;
            const new_row = try void_archetype.append(.{ .id = new_id });
            const void_pointer = Pointer{
                .archetype_index = 0, // void archetype is guaranteed to be first index
                .row_index = new_row,
            };

            self.entities.put(self.allocator, new_id, void_pointer) catch |err| {
                void_archetype.undoAppend();
                return err;
            };
            return new_id;
        }

        pub fn create(self: *Self, comptime T: type, components: T) !EntityID {
            const new_id = self.counter;
            self.counter += 1;

            const Wrapper = reflection.StructWrapperWithId(EntityID, T);

            var hash = reflection.typehash(T);  //@fixme archtype hash of id
            //std.debug.print("\n[1]newhash: {}\n", .{ hash });
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, hash);

            const column_fields = @typeInfo(T).Struct.fields;
            if (!archetype_entry.found_existing) {
                const columns = self.allocator.alloc(Column, column_fields.len + 1) catch |err| {
                    assert(self.archetypes.swapRemove(hash));
                    return err;
                };
                columns[0] = Column.init(.id, EntityID);
                inline for (column_fields) | field, index | {
                    // fixme panic test
                    const name = comptime if (std.meta.stringToEnum(TagType, field.name)) |name| name else @compileError("invalid field name");
                    columns[index + 1] = Column.init(name, field.field_type);    
                }

                std.sort.sort(Column, columns, {}, by_alignment_name);
                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);
                try archetype_entry.value_ptr.ensureUnusedCapacity(10);
            }

            var current_archetype_storage = archetype_entry.value_ptr;

            var row: Wrapper = undefined;
            const component_fields = @typeInfo(T).Struct.fields;
            inline for (component_fields) | f | {                            
                @field(row, f.name) = @field(components, f.name);
            }
            row.id = new_id;
            std.debug.assert(row.id == new_id);

            const row_index = try current_archetype_storage.append(row);
            const entity_pointer = Pointer{
                .archetype_index = @intCast(u16, archetype_entry.index), // void archetype is guaranteed to be first index
                .row_index = row_index,
            };

            self.entities.put(self.allocator, new_id, entity_pointer) catch |err| {
                current_archetype_storage.undoAppend();
                return err;
            };
                       
            return new_id;
        }

        /// Removes an entity.
        pub fn remove(self: *Self, entity: EntityID) !void {
            var archetype = self.archetypeByID(entity);
            const ptr = self.entities.get(entity).?;

            // A swap removal will be performed, update the entity stored in the last row of the
            // archetype table to point to the row the entity we are removing is currently located.
            if (archetype.len > 1) {
                const last_row_entity_id = archetype.get(archetype.len - 1, .id, EntityID).?;
                try self.entities.put(self.allocator, last_row_entity_id, Pointer{
                    .archetype_index = ptr.archetype_index,
                    .row_index = ptr.row_index,
                });
            }

            // Perform a swap removal to remove our entity from the archetype table.
            archetype.remove(ptr.row_index);

            _ = self.entities.remove(entity);
        }

        /// Returns the archetype storage for the given entity.
        pub inline fn archetypeByID(self: *Self, entity: EntityID) *ArchetypeStorage {
            const ptr = self.entities.get(entity).?;
            return &self.archetypes.values()[ptr.archetype_index];
        }

        /// Sets the named component to the specified value for the given entity,
        /// moving the entity from it's current archetype table to the new archetype
        /// table if required.
        pub fn setComponent(
            self: *Self,
            entity: EntityID,
            comptime name: TagType,
            component: std.meta.fieldInfo(TComponents, name).field_type,
        ) !void {
            var archetype = self.archetypeByID(entity);
                
            // Determine the old hash for the archetype.
            const old_hash = archetype.hash;

            // Determine the new hash for the archetype + new component
            var have_already = archetype.hasComponent(name);
            const new_hash = if (have_already) old_hash else old_hash ^ std.hash_map.hashString(@tagName(name));
            std.debug.print("\n[0]newhash: {}\n", .{ new_hash });
            // Find the archetype storage for this entity. Could be a new archetype storage table (if a
            // new component was added), or the same archetype storage table (if just updating the
            // value of a component.)
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);

            // getOrPut allocated, so the archetype we retrieved earlier may no longer be a valid
            // pointer. Refresh it now:
            archetype = self.archetypeByID(entity);

            if (!archetype_entry.found_existing) {
                const columns = self.allocator.alloc(Column, archetype.columns.len + 1) catch |err| {
                    assert(self.archetypes.swapRemove(new_hash));
                    return err;
                };
                mem.copy(Column, columns, archetype.columns);
                columns[columns.len - 1] = Column.init(name, @TypeOf(component));
                std.sort.sort(Column, columns, {}, by_alignment_name);

                archetype_entry.value_ptr.* = ArchetypeStorage.init(self.allocator, columns);
            
            }

            // Either new storage (if the entity moved between storage tables due to having a new
            // component) or the prior storage (if the entity already had the component and it's value
            // is merely being updated.)
            var current_archetype_storage = archetype_entry.value_ptr;

            if (new_hash == old_hash) {
                // Update the value of the existing component of the entity.
                const ptr = self.entities.get(entity).?;
                current_archetype_storage.set(ptr.row_index, name, component);
                return;
            }

            // Copy to all component values for our entity from the old archetype storage (archetype)
            // to the new one (current_archetype_storage).
            const new_row = try current_archetype_storage.appendUndefined();
            const old_ptr = self.entities.get(entity).?;

            // Update the storage/columns for all of the existing components on the entity.
            current_archetype_storage.set(new_row, .id, entity);
            for (archetype.columns) |column| {
                if (column.name == .id) continue;
                for (current_archetype_storage.columns) |corresponding| {
                    if (column.name == corresponding.name) {
                        const old_value_raw = archetype.getRaw(old_ptr.row_index, column.name);
                        current_archetype_storage.setRaw(new_row, corresponding, old_value_raw) catch |err| {
                            current_archetype_storage.undoAppend();
                            return err;
                        };
                        break;
                    }
                }
            }

            // Update the storage/column for the new component.
            current_archetype_storage.set(new_row, name, component);

            archetype.remove(old_ptr.row_index);
            const swapped_entity_id = archetype.get(old_ptr.row_index, .id, EntityID).?;
            // TODO: try is wrong here and below?
            // if we removed the last entry from archetype, then swapped_entity_id == entity
            // so the second entities.put will clobber this one
            try self.entities.put(self.allocator, swapped_entity_id, old_ptr);

            try self.entities.put(self.allocator, entity, Pointer{
                .archetype_index = @intCast(u16, archetype_entry.index),
                .row_index = new_row,
            });
            return;
        }
        
        /// gets the named component of the given type (which must be correct, otherwise undefined
        /// behavior will occur). Returns null if the component does not exist on the entity.
        pub fn getComponent(
            self: *Self,
            entity: EntityID,
            comptime name: TagType,
        ) ? std.meta.fieldInfo(TComponents, name).field_type {
          const Component = comptime std.meta.fieldInfo(TComponents, name).field_type;
          var archetype = self.archetypeByID(entity);

          const ptr = self.entities.get(entity).?;
          return archetype.get(ptr.row_index, name, Component);
        }

        /// Removes the named component from the entity, or noop if it doesn't have such a component.
        pub fn removeComponent(
            self: *Self,
            entity: EntityID,
            comptime name: TagType,
        ) !void {
            var archetype = self.archetypeByID(entity);
            if (!archetype.hasComponent(name)) return;

            // Determine the old hash for the archetype.
            const old_hash = archetype.hash;

            // Determine the new hash for the archetype with the component removed
            var new_hash: u64 = 0;
            for (archetype.columns) |column| {
                if (column.name != name) new_hash ^= std.hash_map.hashString(@tagName(column.name));
            }
            assert(new_hash != old_hash);

            // Find the archetype storage this entity will move to. Note that although an entity with
            // (A, B, C) components implies archetypes ((A), (A, B), (A, B, C)) exist there is no
            // guarantee that archetype (A, C) exists - and so removing a component sometimes does
            // require creating a new archetype table!
            var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);

            // getOrPut allocated, so the archetype we retrieved earlier may no longer be a valid
            // pointer. Refresh it now:
            archetype = self.archetypeByID(entity);

            if (!archetype_entry.found_existing) {
                const columns = self.allocator.alloc(Column, archetype.columns.len - 1) catch |err| {
                    assert(self.archetypes.swapRemove(new_hash));
                    return err;
                };
                var i: usize = 0;
                for (archetype.columns) |column| {
                    if (column.name == name) continue;
                    columns[i] = column;
                    i += 1;
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
            current_archetype_storage.set(new_row, .id, entity);
            for (current_archetype_storage.columns) |column| {
                if (column.name == .id) continue;
                for (archetype.columns) |corresponding| {
                    if (column.name == corresponding.name) {
                        const old_value_raw = archetype.getRaw(old_ptr.row_index, column.name);
                        current_archetype_storage.setRaw(new_row, column, old_value_raw) catch |err| {
                            current_archetype_storage.undoAppend();
                            return err;
                        };
                        break;
                    }
                }
            }

            archetype.remove(old_ptr.row_index);
            const swapped_entity_id = archetype.get(old_ptr.row_index, .id, EntityID).?;
            // TODO: try is wrong here and below?
            // if we removed the last entry from archetype, then swapped_entity_id == entity
            // so the second entities.put will clobber this one
            try self.entities.put(self.allocator, swapped_entity_id, old_ptr);

            try self.entities.put(self.allocator, entity, Pointer{
                .archetype_index = @intCast(u16, archetype_entry.index),
                .row_index = new_row,
            });
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

test "ecc" {
  const Game = struct {
    id: ecs.EntityID,
    location: f32,
    name: []const u8,
    rotation: u32,
  };
  //const Tags = reflection.ToEnum(myGame);
  const MyStorage = Entities(Game);
  const allocator = std.testing.allocator;
  //const Column = MyStorage.Column;
  //const columns = try allocator.alloc(Column, 1);
  //columns[0] = Column.init(.id, EntityID);
  const Entry = struct {
    rotation: u32,
  };

  
  var b = try MyStorage.init(allocator);
  defer b.deinit();
  var e2 = try b.create(Entry, .{ .rotation = 75 });  
  //var ccc = b.getComponent(e2, .rotation);
  try expectEqualOf(u32, 75, b.getComponent(e2, .rotation).?);
  //try expectEqualOf(i32, 75, b.getComponent(e2, .rotation).?);
  var e = try b.new();
  try b.setComponent(e, .rotation, 42);

  const Enemy = struct {
    location: f32,
    rotation: i32
  };


  
  const Result = struct {
    rotation: *u32
  };
  std.debug.print("e2 id: {} -> {}\n", .{ e2, e });
  //var Iter = MyStorage.Iter(&.{ .rotation });
  
  
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
 
  // //try std.testing.expect(iter.next().?.get(Entry).?.rotation == 42);
  try std.testing.expect(iter.next() == null);
   
  var e3 = try b.create(Enemy, .{ .location = 22, .rotation = 55 });
  _ = e3;
  try b.removeComponent(e, .rotation);
  val = b.getComponent(e, .rotation);
  try std.testing.expect(val == null);
  try b.remove(e);
}

fn expectEqualOf(comptime T: type, expected: T, actual: T) !void {
  return std.testing.expectEqual(expected, actual);
}

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