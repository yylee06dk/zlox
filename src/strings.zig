const std = @import("std");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const table = @import("table.zig");

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

fn allocateString(totalLength: usize, string: []const u8, hash: u32, gcAlloc: *memory.GCAllocator, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*ObjectString {
    const allocation = try alloc.alignedAlloc(u8, .of(ObjectString), totalLength);
    errdefer alloc.free(allocation);
    const ptr: *ObjectString = @ptrCast(allocation);
    try gcAlloc.addAllocation(@ptrCast(ptr), totalLength, alloc);

    ptr.* = ObjectString{
        .object = .{ .kind = .String },
        .length = @intCast(totalLength - @sizeOf(ObjectString)),
        .hash = hash,
    };

    @memcpy(allocation[@sizeOf(ObjectString)..], string);

    _ = try stringPool.set(ptr, .{ .nil = 1 }, alloc);

    return @ptrCast(ptr);
}

pub fn makeString(start: []const u8, length: usize, gcAlloc: *memory.GCAllocator, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*ObjectString {
    const string = start[0..length];
    // Calculate hash of string
    const hash = std.hash.Fnv1a_32.hash(string);

    // Check if the same string is in string pool (Must check it "deeply")
    const checkPool: ?*ObjectString = stringPool.contains(string, hash);
    if (checkPool) |s| {
        return s;
    }

    const totalLength = @sizeOf(ObjectString) + length;
    return try allocateString(totalLength, string, hash, gcAlloc, stringPool, alloc);
}
