const std = @import("std");

pub const TypeId = enum(usize) { _ };

// typeId implementation by Felix "xq" Queißner
pub fn typeId(comptime T: type) TypeId {
    _ = T;
    return @intToEnum(TypeId, @ptrToInt(&struct {
        var x: u8 = 0;
    }.x));
}

pub fn ToEnum(comptime components: anytype) type {
  return Blk: {
      const fields = std.meta.fields(@TypeOf(components));
      var tags: [fields.len + 1] std.builtin.Type.EnumField = undefined;
      tags[0] = .{
        .name = "id",
        .value = 0
      };
      inline for (fields, 0..) |f, i| {
          tags[i + 1] = .{
              .name = f.name,
              .value = i + 1,
          };
      }
      const type_info = std.builtin.Type{ 
          .Enum = .{
              .tag_type = u32,
              .fields = &tags,
              .decls = &.{},
              .is_exhaustive = true,
          }
      };
      break :Blk @Type(type_info);
  };
}

pub fn ToEnumFromNames(comptime names: []const []const u8) type {
  const Type = std.builtin.Type;
  return Blk: {
      var tags: [names.len] Type.EnumField = undefined;
      inline for (names, 0..) |name, i| {
          tags[i] = .{
              .name = name,
              .value = i,
          };
      }
      const type_info = Type{ 
          .Enum = .{
              .tag_type = std.math.IntFittingRange(0, names.len - 1),
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
      inline for (fields, 0..) |f, i| {
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
      inline for (fields, 0..) |f, i| {
        //tags[i] = comptime std.meta.stringToEnum(TagType, f.name).?;           
        tags[i] = @field(TagType, f.name);
      }
      break :Blk tags[0..];
  };
}

pub fn tagsToString(comptime T: type, comptime tags: []const T) []const []const u8 {
    return blk: {
        var array: [tags.len] []const u8 = undefined;
        inline for (tags, 0..) | t, i | {
            array[i] = @tagName(t);
        }
        break :blk array[0..];
    };
}

pub fn typesToHolder(comptime types: []const type) type {
    var fields: [types.len] std.builtin.Type.StructField = undefined;
    inline for (types, 0..) | t, index | {
        //const t_info_optional = std.builtin.TypeInfo { .Optional = .{ .child = t } };
        fields[index] = .{
            .name =  t.name,
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

pub fn StructWrapperWithId(comptime idType: type, comptime componentType: type) type {
    return blk: {
        const old_fields = std.meta.fields(componentType);
        var new_fields: [old_fields.len + 1] std.builtin.Type.StructField = undefined;
        new_fields[0] = .{
            .name = "id",
            .type = idType,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(idType) > 0) @alignOf(idType) else 0,
        };
        inline for (old_fields, 0..) | old_field, index | {
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
    for (array) | each | {
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
    inline for (types) | each | {
        const decls = getDeclsFn(each);
        inline for (decls) | dcl | {
            const fn_info = dcl.func;
            if (fn_info.params.len == 2) {
                const argt_0 = fn_info.params[0].type;
                const argt_1 = fn_info.params[1].type;
                if (argt_0 == each and argt_1 == *T) {
                    if (!contains(names, dcl.name)) {
                    names = names ++ &[_][]const u8{ dcl.name };
                    }
                }
            } 
            else if (fn_info.params.len == 1) {
                const argt_0 = fn_info.params[0].type;
                if (argt_0 == *T) {
                    if (!contains(names, dcl.name)) {
                        names = names ++ &[_][]const u8{ dcl.name };
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
            if (info == .Fn){
                array[count] = Entry{ .name = decl.name, .func = info.Fn };
                count += 1;
            }            
        }
        return array[0..count];
    }
}
