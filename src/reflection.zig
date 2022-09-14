const std = @import("std");

const TypeId = enum(usize) { _ };

// typeId implementation by Felix "xq" Queißner
pub fn typeId(comptime T: type) TypeId {
    _ = T;
    return @intToEnum(TypeId, @ptrToInt(&struct {
        var x: u8 = 0;
    }.x));
}

pub fn ToEnum(components: anytype) type {
  return Blk: {
      const fields = std.meta.fields(@TypeOf(components));
      var tags: [fields.len + 1] std.builtin.Type.EnumField = undefined;
      tags[0] = .{
        .name = "id",
        .value = 0
      };
      inline for (fields) |f, i| {
          tags[i + 1] = .{
              .name = f.name,
              .value = i + 1,
          };
      }
      const type_info = std.builtin.Type{ 
          .Enum = .{
              .layout = .Auto,
              .tag_type = u32,
              .fields = &tags,
              .decls = &.{},
              .is_exhaustive = true,
          }
      };
      break :Blk @Type(type_info);
  };
}

pub fn EnumFromType(comptime T: type) type {
    return Blk: {
      const fields = std.meta.fields(T);
      var tags: [fields.len + 1] std.builtin.Type.EnumField = undefined;
      tags[0] = .{
        .name = "id",
        .value = 0
      };
      inline for (fields) |f, i| {
          tags[i + 1] = .{
              .name = f.name,
              .value = i + 1,
          };
      }
      const type_info = std.builtin.Type{ 
          .Enum = .{
              .layout = .Auto,
              .tag_type = u32,
              .fields = &tags,
              .decls = &.{},
              .is_exhaustive = true,
          }
      };
      break :Blk @Type(type_info);
  };
}

pub fn extract(comptime ValueT: type, comptime TagType: type) []const TagType {
    return Blk: {
      const fields = std.meta.fields(ValueT);
      var tags: [fields.len] TagType = undefined;
      inline for (fields) |f, i| {
        tags[i] = std.meta.stringToEnum(TagType, f.name).?;           
      }
      break :Blk tags[0..];
  };
}

pub fn tagsToString(comptime T: type, comptime tags: []const T) []const []const u8 {
    return blk: {
        var array: [tags.len] []const u8 = undefined;
        inline for (tags) | t, i | {
            array[i] = @tagName(t);
        }
        break :blk array[0..];
    };
}

pub fn typesToHolder(comptime types: []const type) type {
    var fields: [types.len] std.builtin.Type.StructField = undefined;
    inline for (types) | t, index | {
        const t_info_optional = std.builtin.TypeInfo { .Optional = .{ .child = t } };
        fields[index] = .{
            .name =  t.name,
            .field_type = @Type(t_info_optional),
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

// pub fn extractTag(comptime tagType: type, name: []const u8) ?@TypeOf(tagType) {
//     return Blk : {
//         const f = std.meta.stringToEnum
//         const fields = std.meta.fields(tagType);
//         inline for (fields) | field | {
//             if (std.mem.eql(field.name, name)) {
//                 break :Blk 
//             }
//         }
//         break :Blk null;
//     };
// }

pub fn StructWrapperWithId(comptime idType: type, comptime componentType: type) type {
    return blk: {
        const old_fields = std.meta.fields(componentType);
        var new_fields: [old_fields.len + 1] std.builtin.Type.StructField = undefined;
        new_fields[0] = .{
            .name = "id",
            .field_type = idType,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(idType) > 0) @alignOf(idType) else 0,
        };
        inline for (old_fields) | old_field, index | {
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

pub fn typehash(comptime T: type) u64 {
    return blk: {
        var hash: u64 = std.math.maxInt(u64);
        for (std.meta.fieldNames(T)) | name | {
            hash ^= std.hash_map.hashString(name);
        }
        break :blk hash;
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

    var argument_field_list: [function_info.args.len]std.builtin.Type.StructField = undefined;
    inline for (function_info.args) |arg, i| {
        const T = arg.arg_type.?;
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