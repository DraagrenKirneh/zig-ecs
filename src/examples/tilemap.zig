const std = @import("std");

pub const Tile = enum {
    empty,
    tower,
    path,
    spawn,
    goal,
};

const TileMap: []Tile = &[]Tile{
    .goal,  .tower, .empty,
    .path,  .path,  .path,
    .empty, .tower, .spawn,
};

pub fn find(tile: Tile, map: []const Tile) ?usize {
    for (map) | each, index | {
        if (each == tile) return index;
    }
    return null;
}


fn getTop(index: usize, width: usize) ?usize {
    if (index < width) return null;
    return index - width;
}

fn getLeft(index: usize, width: usize) ?usize { 
    if (index % width == 0) return null;
    return index - 1;
}

fn getRight(index: usize, width: usize) ?usize {
    if (index % width == width - 1) return null;
    return index + 1;
}

fn getBottom(index: usize, width: usize, height: usize) ?usize {
    var tmp = index + width;
    if (tmp >= width * height) return null;
    return tmp;
}

pub fn createPath(alloc: std.mem.Allocator, width: usize, height: usize, map: []const Tile) ![]const usize {
    var list = std.ArrayList(usize).init(alloc);

    var currentIndex = find(.spawn, map);
    var lastIndex = currentIndex;
    if (currentIndex) | ix | {
        try list.append(ix);
    } else {
        return error.TileMissingSpawn;
    }

    var done = false;
    while (!done) {
        var c = currentIndex;
        if(getLeft(currentIndex, width)) | i | {
            if (i != lastIndex) {
                if (map[i] == .path) {
                    try list.append(i);
                    lastIndex = currentIndex;
                    currentIndex = i;
                }
                else if (map[i] == .goal) { 
                    try list.append(i);
                    done = true; 
                }
            }              
        }
        if(getRight(currentIndex, width)) | i | {
            if (i != lastIndex) {
                if (map[i] == .path) {
                    try list.append(i);
                    lastIndex = currentIndex;
                    currentIndex = i;
                }
                else if (map[i] == .goal) { 
                    try list.append(i);
                    done = true; 
                }
            }              
        }
        if(getTop(currentIndex, width)) | i | {
            if (i != lastIndex) {
                if (map[i] == .path) {
                    try list.append(i);
                    lastIndex = currentIndex;
                    currentIndex = i;
                }
                else if (map[i] == .goal) { 
                    try list.append(i);
                    done = true; 
                }
            }              
        }
        if(getBottom(currentIndex, width, height)) | i | {
            if (i != lastIndex) {
                if (map[i] == .path) {
                    try list.append(i);
                    lastIndex = currentIndex;
                    currentIndex = i;
                }
                else if (map[i] == .goal) { 
                    try list.append(i);
                    done = true; 
                }
            }              
        }
        if (c == currentIndex) return error.invalidPath;
    }

    return list.toOwnedSlice();
    
}

test "getBottom" {
    var g: []const ?usize = &.{
        3, 4, 5,
        6, 7, 8,
        null, null, null
    };
    for (g) | each, index | {
        var r  = getBottom(index, 3, 3);
        if (each == null) { try std.testing.expect(r == null); }
        else { try std.testing.expectEqual(each, r.?); }
    }
}

test "getTop" {
    var g: []const ?usize = &.{
        null, null, null,
        0, 1, 2,
        3, 4, 5,
        
    };
    for (g) | each, index | {
        var r  = getTop(index, 3);
        if (each == null) { try std.testing.expect(r == null); }
        else { try std.testing.expectEqual(each, r.?); }
    }
}


test "getLeft" {
    var g: []const ?usize = &.{
        null, 0, 1,
        null, 3, 4,
        null, 6, 7,
    };
    for (g) | each, index | {
        var r  = getLeft(index, 3);
        if (each == null) { try std.testing.expect(r == null); }
        else { try std.testing.expectEqual(each, r.?); }
    }
}


test "getRight" {
    var g: []const ?usize = &.{
        1, 2, null,
        4, 5, null,
        7, 8, null,
    };
    for (g) | each, index | {
        var r  = getRight(index, 3);
        if (each == null) { try std.testing.expect(r == null); }
        else { try std.testing.expectEqual(each, r.?); }
    }
}

test "createPath" {
    
}
