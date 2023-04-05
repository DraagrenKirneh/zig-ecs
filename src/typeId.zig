pub const TypeId = enum(usize) { _ };

// typeId implementation by Felix "xq" Queißner
pub fn typeId(comptime T: type) TypeId {
    return @intToEnum(TypeId, typeIdValue(T));
}

pub fn typeIdValue(comptime T: type) usize {
    _ = T;
    return @ptrToInt(&struct {
        var x: u8 = 0;
    }.x);
}
