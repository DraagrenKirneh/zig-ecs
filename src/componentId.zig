const std = @import("std");

const Field = std.builtin.Type.StructField;

pub fn ComponentIdResolver(comptime ComponentTag: type) type {
    return struct {
        pub fn fromField(comptime field: Field) ComponentId {
            if (@typeInfo(field.type) != .Struct) return fromName(field.name);
            return if (@hasDecl(field.type, "key_tag"))
                fromPair(field.type)
            else if (@hasDecl(field.type, "wildcard_tag"))
                fromWildcard(field.type)
            else
                fromName(field.name);
        }

        fn fromPair(comptime Pair: type) ComponentId {
            return ComponentId{
                .component_a = @enumToInt(Pair.key_tag),
                .component_b = @enumToInt(Pair.value_tag),
                .pair = 1,
            };
        }

        fn fromWildcard(comptime Wildcard: type) ComponentId {
            return ComponentId{ .component_a = @enumToInt(Wildcard.wildcard_tag), .wildcard = 1 };
        }

        fn fromName(comptime name: []const u8) ComponentId {
            const tag = comptime std.meta.stringToEnum(ComponentTag, name).?;
            return ComponentId.initComponent(@enumToInt(tag));
        }
    };
}

pub const ComponentId = packed struct {
    component_a: u14 = 0,
    component_b: u14 = 0,
    reserved: u2 = 0,
    pair: u1 = 0,
    wildcard: u1 = 0,

    const Self = @This();

    pub inline fn initComponent(val: u14) Self {
        return Self{ .component_a = val };
    }

    pub inline fn initPair(a: u14, b: u14) Self {
        return Self{ .component_a = a, .component_b = b, .pair = 1 };
    }

    pub inline fn equal(self: Self, other: Self) bool {
        return @bitCast(u32, self) == @bitCast(u32, other);
    }

    pub inline fn isWildcardOf(self: Self, other: Self) bool {
        return self.wildcard == 1 and other.pair == 1 and self.component_a == other.component_a;
    }

    pub inline fn isEntityId(self: Self) bool {
        return @bitCast(u32, self) == 0;
    }

    pub inline fn value(self: Self) u32 {
        return @bitCast(u32, self);
    }

    pub fn Resolver(comptime Tag: type) type {
        return ComponentIdResolver(Tag);
    }
};
