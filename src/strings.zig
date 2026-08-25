const std = @import("std");
const memory = @import("memory.zig");
const objects = @import("objects.zig");

const Allocator = std.mem.Allocator;

pub const ObjectString = struct {
    object: objects.Object,
    length: u32,
    hash: u32,
    // Characters trail (raw bytes of info)
    pub fn getString(self: *const ObjectString) []const u8 {
        const selfAsBytes: [*]const u8 = @ptrCast(@alignCast(self));
        return selfAsBytes[@sizeOf(ObjectString)..][0..self.length];
    }
};

pub fn allocateString(totalLength: usize, string: []const u8, gcAlloc: *memory.GCAllocator, alloc: Allocator) Allocator.Error!*ObjectString {
    const allocation = try alloc.alignedAlloc(u8, .of(ObjectString), totalLength);
    errdefer alloc.free(allocation);
    const ptr: *ObjectString = @ptrCast(allocation);
    try gcAlloc.addAllocation(@ptrCast(ptr), totalLength, alloc);

    ptr.* = ObjectString{
        .object = .{ .kind = .String },
        .length = @intCast(totalLength - @sizeOf(ObjectString)),
    };

    @memcpy(allocation[@sizeOf(ObjectString)..], string);

    return @ptrCast(ptr);
}

pub fn makeString(start: []const u8, length: usize, gcAlloc: *memory.GCAllocator, alloc: Allocator) Allocator.Error!*ObjectString {
    const totalLength = @sizeOf(ObjectString) + length;
    const string = start[0..length];
    return try allocateString(totalLength, string, gcAlloc, alloc);
}
