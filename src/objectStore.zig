const std = @import("std");
const bci = @import("bytecodeInfo.zig");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const table = @import("table.zig");

const Allocator = std.mem.Allocator;

pub fn makeString(start: []const u8, length: usize, gcAlloc: *memory.GCAllocator, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*objects.Object.String {
    const string = start[0..length];
    const hash = std.hash.Fnv1a_32.hash(string);

    if (stringPool.contains(string, hash)) |interned| {
        return interned;
    }

    const totalLength = @sizeOf(objects.Object.String) + length;
    return allocateString(totalLength, string, hash, gcAlloc, stringPool, alloc);
}

fn allocateString(totalLength: usize, string: []const u8, hash: u32, gcAlloc: *memory.GCAllocator, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*objects.Object.String {
    const allocation = try alloc.alignedAlloc(u8, .of(objects.Object.String), totalLength);
    errdefer alloc.free(allocation);

    const strPtr: *objects.Object.String = @ptrCast(allocation);
    strPtr.* = .{
        .length = @intCast(totalLength - @sizeOf(objects.Object.String)),
        .hash = hash,
    };

    @memcpy(allocation[@sizeOf(objects.Object.String)..], string);

    try gcAlloc.addAllocation(.{ .string = strPtr }, totalLength, alloc);
    _ = try stringPool.set(strPtr, .{ .nil = 1 }, alloc);

    return strPtr;
}

pub fn createEmptyFunction(alloc: Allocator, gcAlloc: *memory.GCAllocator) Allocator.Error!*objects.Object.Function {
    const funcPtr = try alloc.create(objects.Object.Function);
    errdefer alloc.destroy(funcPtr);

    try gcAlloc.addAllocation(.{ .function = funcPtr }, @sizeOf(objects.Object.Function), alloc);
    return funcPtr;
}

pub fn initFunctionInplace(self: *objects.Object.Function, alloc: Allocator, gcAlloc: *memory.GCAllocator, name: ?*const objects.Object.String, chunk: bci.Chunk, arity: u8) Allocator.Error!void {
    const nameTrueSize = @as(usize, if (name) |n| n.length else 0);
    const chunkTrueSize = chunk.codeSlice.len * @sizeOf(u8) + std.mem.sliceAsBytes(chunk.constantSlice).len + chunk.lineSlice.len * @sizeOf(usize);

    try gcAlloc.addAllocation(.{ .function = self }, nameTrueSize + chunkTrueSize, alloc);
    self.name = name;
    self.chunk = chunk;
    self.arity = arity;
}
