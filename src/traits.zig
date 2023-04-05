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

const ArchetypeId = u64;

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
