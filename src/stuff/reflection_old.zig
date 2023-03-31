// --------------------------------- //

const std = @import("std");

pub fn Custom_FieldType(comptime T: type, comptime field: Custom_FieldEnum(T)) type {
    if (@typeInfo(T) != .Struct and @typeInfo(T) != .Union) {
        @compileError("Expected struct or union, found '" ++ @typeName(T) ++ "'");
    }

    return custom_fieldInfo(T, field).type;
}

const Type = std.builtin.Type;

pub fn custom_fieldInfo(comptime T: type, comptime field: Custom_FieldEnum(T)) switch (@typeInfo(T)) {
    .Struct => Type.StructField,
    else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
} {
    return std.meta.fields(T)[@enumToInt(field)];
}

pub fn MakeExhausive(comptime T: type, comptime S: type) type {
    const oldEnum = std.meta.FieldEnum(T);
    const fields = std.meta.fields(oldEnum);
    return @Type(.{
        .Enum = .{
            .tag_type = S,
            .fields = fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

// Returns an enum with a variant named after each field of `T`.
pub fn Custom_FieldEnum(comptime T: type) type {
    const field_infos = std.meta.fields(T);

    if (field_infos.len == 0) {
        return @Type(.{
            .Enum = .{
                .tag_type = u0,
                .fields = &.{},
                .decls = &.{},
                .is_exhaustive = true,
            },
        });
    }

    var enumFields: [field_infos.len]std.builtin.Type.EnumField = undefined;
    var decls = [_]std.builtin.Type.Declaration{};
    inline for (field_infos, 0..) |field, i| {
        enumFields[i] = .{
            .name = field.name,
            .value = i,
        };
    }
    return @Type(.{
        .Enum = .{
            .tag_type = u32,
            .fields = &enumFields,
            .decls = &decls,
            .is_exhaustive = false,
        },
    });
}
