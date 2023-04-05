const std = @import("std");

pub fn ToEnumFromNames(comptime names: []const []const u8) type {
    //const Type = std.builtin.Type;
    return Blk: {
        var tags: [names.len]std.builtin.Type.EnumField = undefined;
        inline for (names, 0..) |name, i| {
            tags[i] = .{
                .name = name,
                .value = i,
            };
        }
        const type_info = std.builtin.Type{ .Enum = .{
            .tag_type = std.math.IntFittingRange(0, names.len - 1),
            .fields = &tags,
            .decls = &.{},
            .is_exhaustive = true,
        } };
        break :Blk @Type(type_info);
    };
}

pub fn EnumFromType(comptime T: type) type {
    return Blk: {
        const fields = std.meta.fields(T);
        var tags: [fields.len + 1]std.builtin.Type.EnumField = undefined;
        tags[0] = .{ .name = "id", .value = 0 };
        inline for (fields, 0..) |f, i| {
            tags[i + 1] = .{
                .name = f.name,
                .value = i + 1,
            };
        }
        const type_info = std.builtin.Type{ .Enum = .{
            .layout = .Auto,
            .tag_type = u32,
            .fields = &tags,
            .decls = &.{},
            .is_exhaustive = true,
        } };
        break :Blk @Type(type_info);
    };
}

pub fn ComponentUnion(comptime T: type) type {
    const fields = std.meta.fields(T);
    var union_fields: [fields.len]std.builtin.Type.UnionField = undefined;
    inline for (fields, 0..) |namespace, i| {
        //const component_enum = std.meta.FieldEnum(namespace.type);
        union_fields[i] = .{
            .name = namespace.name,
            .type = namespace.type,
            .alignment = @alignOf(namespace.type),
        };
    }

    // need type_info variable (rather than embedding in @Type() call)
    // to work around stage 1 bug
    const type_info = std.builtin.Type{
        .Union = .{
            .layout = .Auto,
            .tag_type = std.meta.FieldEnum(T),
            .fields = &union_fields,
            .decls = &.{},
        },
    };
    return @Type(type_info);
}

pub fn StructWrapperWithId(comptime idType: type, comptime componentType: type) type {
    if (componentType == void) return struct { id: idType };
    if (@hasField(componentType, "id")) {
        //std.debug.assert(@TypeOf(componentType.id) == idType);  // fixme validate or?
        return componentType;
    }
    return blk: {
        const old_fields = std.meta.fields(componentType);
        var new_fields: [old_fields.len + 1]std.builtin.Type.StructField = undefined;
        new_fields[0] = .{
            .name = "id",
            .type = idType,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(idType) > 0) @alignOf(idType) else 0,
        };
        inline for (old_fields, 0..) |old_field, index| {
            new_fields[index + 1] = old_field;
        }
        const type_info = std.builtin.Type{
            .Struct = .{
                .layout = .Auto,
                .fields = &new_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        };
        break :blk @Type(type_info);
    };
}

pub fn NamedArgsTuple(comptime Function: type, names: []const []const u8) type {
    const info = @typeInfo(Function);
    if (info != .Fn)
        @compileError("ArgsTuple expects a function type");

    const function_info = info.Fn;
    if (function_info.is_generic)
        @compileError("Cannot create ArgsTuple for generic function");
    if (function_info.is_var_args)
        @compileError("Cannot create ArgsTuple for variadic function");

    var argument_field_list: [function_info.params.len]std.builtin.Type.StructField = undefined;
    inline for (function_info.params, 0..) |arg, i| {
        const T = arg.type.?;
        argument_field_list[i] = .{
            .name = names[i],
            .field_type = T,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(T) > 0) @alignOf(T) else 0,
        };
    }

    return @Type(.{
        .Struct = .{
            .is_tuple = true,
            .layout = .Auto,
            .decls = &.{},
            .fields = &argument_field_list,
        },
    });
}

fn contains(comptime array: []const []const u8, comptime item: []const u8) bool {
    for (array) |each| {
        if (std.mem.eql(u8, each, item)) return true;
    }
    return false;
}

pub fn ToEnumFromMethods(comptime T: type, comptime types: []const type) type {
    const names = getDeclEnumNames(T, types);
    return ToEnumFromNames(names);
}

// specialized for pipeline
pub fn getDeclEnumNames(comptime T: type, comptime types: []const type) []const []const u8 {
    comptime var names: []const []const u8 = &[_][]const u8{};
    inline for (types) |each| {
        const decls = getDeclsFn(each);
        inline for (decls) |dcl| {
            const fn_info = dcl.func;
            if (fn_info.params.len == 2) {
                const argt_0 = fn_info.params[0].type;
                const argt_1 = fn_info.params[1].type;
                if (argt_0 == each and argt_1 == *T) {
                    if (!contains(names, dcl.name)) {
                        names = names ++ &[_][]const u8{dcl.name};
                    }
                }
            } else if (fn_info.params.len == 1) {
                const argt_0 = fn_info.params[0].type;
                if (argt_0 == *T) {
                    if (!contains(names, dcl.name)) {
                        names = names ++ &[_][]const u8{dcl.name};
                    }
                }
            }
        }
    }
    return names;
}

const Entry = struct {
    name: []const u8,
    func: std.builtin.Type.Fn,
};

fn getDeclsFn(comptime T: type) []const Entry {
    comptime {
        const decls = @typeInfo(T).Struct.decls;
        var count = 0;
        var array: [decls.len]Entry = undefined;
        for (decls) |decl| {
            if (!decl.is_pub) continue;
            const field = @field(T, decl.name);
            const info = @typeInfo(@TypeOf(field));
            if (info == .Fn) {
                array[count] = Entry{ .name = decl.name, .func = info.Fn };
                count += 1;
            }
        }
        return array[0..count];
    }
}

pub fn Pair(comptime A: type, comptime B: type, comptime Tag: type, comptime tagA: Tag, comptime tagB: Tag) type {
    if (A == void and B == void) return packed struct {
        pub const key_tag: Tag = tagA;
        pub const value_tag: Tag = tagB;
        key: A = {},
        value: B = {},
    };
    if (A == void) return packed struct {
        pub const key_tag: Tag = tagA;
        pub const value_tag: Tag = tagB;
        key: A = {},
        value: B,
    };
    if (B == void) return packed struct {
        pub const key_tag: Tag = tagA;
        pub const value_tag: Tag = tagB;
        key: A,
        value: B = {},
    };
    return packed struct {
        pub const key_tag: Tag = tagA;
        pub const value_tag: Tag = tagB;
        key: A,
        value: B,
    };
}

test "pair" {
    const Tag = enum { Any };
    const P = Pair(void, void, Tag, .Any, .Any);
    try std.testing.expect(@sizeOf(P) == 0);
}
