const std = @import("std");
const ecs = @import("ecs");
const refl = ecs.refl;

const MyType = struct {
    types: []const type = &[_]type{},
    resources: []const type = &[_]type{},
    systems: []const type = &[_]type{},

    const Self = @This();

    inline fn init() Self {
        return .{};
    }

    inline fn create(comptime items: []const type) Self {
        return .{ .types = items };
    }

    inline fn add(comptime self: Self, comptime entry: type) Self {
        return create(self.types ++ &[_]type{entry});
    }

    inline fn addResource(comptime self: Self, comptime entry: type) Self {
        return create(self.types ++ &[_]type{entry});
    }

    pub fn BuildResources(comptime self: Self) type {
        return refl.typesToHolder(self.resources);
    }
};

pub fn typesToHolder(comptime types: []const type) type {
    var fields: [types.len]std.builtin.Type.StructField = undefined;
    inline for (types, 0..) |t, index| {
        //const t_info_optional = std.builtin.TypeInfo { .Optional = .{ .child = t } };
        fields[index] = .{
            .name = t.name,
            .type = t, //@Type(t_info_optional),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(t) > 0) @alignOf(t) else 0,
        };
    }
    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &.{},
            .fields = &fields,
        },
    });
}

test "akka" {
    const len = MyType.init()
    //.create(&[_]type{EntityID})
        .add(*i32)
        .addResource(ecs.EntityID)
        .BuildResources();

    try @import("std").testing.expect(@typeInfo(len) == .Struct);
}

// const PairTrait = trait.multiTrait(.{
//     trait.hasField("key"),
//     trait.hasField("value"),
//     trait.hasDecls(comptime T: type, comptime names: anytype)
// });

// fn higestComponentId(comptime T: type) usize {
//     var max = 0;
//     inline for (std.meta.fields(T)) |field| {
//         const value = reflection.getComponentId(TagType, field.type, field.name);
//         max = std.math.max(max, value);
//     }
// }
