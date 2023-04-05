// pub fn ArchetypeIndexes(comptime Tag: type) type {
//     return struct {
//         const ComponentCount = std.meta.fields(Tag).len;
//         const Set = std.AutoHashMapUnmanaged(u16, void);
//         const Map = std.AutoHashMapUnmanaged(usize, Set);

//         const emptySet: Set = .{};

//         allocator: Allocator,
//         components: [ComponentCount]Set = undefined,
//         wildcards: [ComponentCount]Set = undefined,
//         pairs: Map = .{},

//         const Self = @This();

//         pub fn init(allocator: Allocator) Self {
//             var self = Self{ .allocator = allocator };

//             for (0..ComponentCount) |i| {
//                 self.components[i] = .{};
//                 self.wildcards[i] = .{};
//             }

//             return self;
//         }

//         pub fn deinit(self: *Self) void {
//             for (0..ComponentCount) |i| {
//                 self.components[i].deinit(self.allocator);
//                 self.wildcards[i].deinit(self.allocator);
//             }
//             var it = self.pairs.valueIterator();
//             while (it.next()) |value_ptr| {
//                 value_ptr.deinit(self.allocator);
//             }
//             self.pairs.deinit(self.allocator);
//         }

//         pub fn getComponentIndexIterator(self: *const Self, tag: Tag) Set.KeyIterator {
//             return self.components[@enumToInt(tag)].keyIterator();
//         }

//         pub fn hasComponent(self: *const Self, tag: Tag, index: u16) bool {
//             return self.components[@enumToInt(tag)].contains(index);
//         }

//         pub fn hasPair(self: *const Self, id: usize, index: u16) bool {
//             return if (self.pairs.get(id)) |set| set.contains(index) else false;
//         }

//         pub fn hasWildcard(self: *const Self, tag: Tag, index: u16) bool {
//             return self.wildcards[@enumToInt(tag)].contains(index);
//         }

//         pub fn haveItem(self: *const Self, tag: Tag, id: usize, index: u16) bool {
//             if (id < ComponentCount) return self.components[id].contains(index);
//             if (id & reflection.highBit == 0) return self.hasPair(id, index);
//             return self.wildcards[@enumToInt(tag)].contains(index);
//         }

//         pub fn getSetIterator(self: *const Self, comptime T: type, id: usize) Set.KeyIterator {
//             if (id < ComponentCount) return self.components[id].keyIterator();
//             if (id & reflection.highBit == reflection.highBit) {
//                 if (@hasDecl(T, "tag")) {
//                     const t_info: Tag = @field(T, "tag");
//                     return self.wildcards[@enumToInt(t_info)].keyIterator();
//                 }
//                 return emptySet.keyIterator();
//             }
//             if (self.pairs.get(id)) |k| return k.keyIterator();
//             return emptySet.keyIterator();
//         }

//         pub fn register(self: *Self, comptime T: type, id: usize, index: u16) !void {
//             if (id < ComponentCount) return self.registerComponent(id, index);
//             return self.registerPair(T, id, index);
//         }

//         pub fn registerPair(self: *Self, comptime T: type, id: usize, archetypeIndex: u16) !void {
//             var pair_entry = try self.pairs.getOrPut(self.allocator, id);
//             if (!pair_entry.found_existing) {
//                 pair_entry.value_ptr.* = .{};
//             }
//             try pair_entry.value_ptr.put(self.allocator, archetypeIndex, {});
//             if (@typeInfo(T) == .Struct and @hasDecl(T, "firstTag")) {
//                 const tag = @field(T, "firstTag");
//                 try self.wildcards[@enumToInt(tag)].put(self.allocator, archetypeIndex, {});
//             }
//         }

//         pub fn registerComponent(self: *Self, tag: usize, archetypeIndex: u16) !void {
//             return self.components[tag].put(self.allocator, archetypeIndex, {});
//         }

//         pub fn IndexIterator(comptime T: type) type {
//             return struct {
//                 const fields = std.meta.fields(T);

//                 indexes: *const Self,
//                 iterator: Self.Set.KeyIterator = undefined,

//                 const Iterator = @This();

//                 pub fn init(indexes: *const Self) Iterator {
//                     const ix = fields.len - 1;
//                     const cid =  getComponentId(Tag, fields[ix].type, fields[ix].name);
//                     //const existingTag = comptime std.meta.stringToEnum(Tag, fields[ix].name).?;

//                     return .{
//                         .indexes = indexes,
//                         .iterator = indexes.getSetIterator(fields[ix].type, cid),
//                     };
//                 }

//                 pub fn next(it: *Iterator) ?u16 {
//                     loop: while (it.iterator.next()) |archetype| {
//                         inline for (1..fields.len) |fIndex| {
//                             const field = fields[fields.len - fIndex - 1];
//                             const id = reflection.getComponentId(Tag, field.type, field.name);
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

// pub fn extract(comptime ValueT: type, comptime TagType: type) []const TagType {
//     return Blk: {
//         const fields = std.meta.fields(ValueT);
//         var tags: [fields.len]TagType = undefined;
//         inline for (fields, 0..) |f, i| {
//             //tags[i] = comptime std.meta.stringToEnum(TagType, f.name).?;
//             tags[i] = @field(TagType, f.name);
//         }
//         break :Blk tags[0..];
//     };
// }

// pub fn TypedIter2(comptime T: type, comptime E: type) type {
//     return struct {
//         entities: *const E,
//         archetype_index: usize = 0,
//         row_index: u32 = 0,

//         const Iterator = @This();
//         const Components = extractComponentIds(T);
//         const isSimple = blk: {
//             inline for (Components) |cid| {
//                 if (cid >= PackedColumnId.WildcardMask) break :blk false;
//             }
//             break :blk true;
//         };

//         pub fn init(entities: *const E) Iterator {
//             var iterator = Iterator{
//                 .entities = entities,
//             };

//             return iterator;
//         }

//         pub fn simpleNext(iter: *Iterator) ?T {
//             const entities = iter.entities;
//             // If the archetype table we're looking at does not contain the components we're
//             // querying for, keep searching through tables until we find one that does.
//             var archetype = entities.archetypes.entries.get(iter.archetype_index).value;
//             while (!hasComponents(archetype, Components) or iter.row_index >= archetype.len) {
//                 iter.archetype_index += 1;
//                 iter.row_index = 0;
//                 if (iter.archetype_index >= entities.archetypes.count()) {
//                     return null;
//                 }
//                 archetype = entities.archetypes.entries.get(iter.archetype_index).value;
//             }

//             var row_index = iter.row_index;
//             iter.row_index += 1;
//             return archetype.getInto(row_index, T);
//         }

//         pub fn advancedNext(iter: *Iterator) ?T {
//             const entities = iter.entities;
//             // If the archetype table we're looking at does not contain the components we're
//             // querying for, keep searching through tables until we find one that does.
//             var archetype = entities.archetypes.entries.get(iter.archetype_index).value;

//             while (!hasComponents(archetype, Components) or iter.row_index >= archetype.len) {
//                 iter.archetype_index += 1;
//                 iter.row_index = 0;
//                 if (iter.archetype_index >= entities.archetypes.count()) {
//                     return null;
//                 }
//                 archetype = entities.archetypes.entries.get(iter.archetype_index).value;
//             }

//             var row_index = iter.row_index;
//             iter.row_index += 1;
//             var res = archetype.getInto(row_index, T);
//             inline for (std.meta.fields(T)) |f| {
//                 if (@hasDecl(f, "wildcard_tag")) {
//                     @field(res, f.name) = f.type.initIterator(iter.archetype, iter.row_index, 0);
//                 }
//             }
//             return res;
//         }

//         pub fn next(iter: *Iterator) ?T {
//             //if (isSimple) return iter.simpleNext();
//             return iter.advancedNext();
//         }
//     };
// }
