const std = @import("std");
const bci = @import("bytecodeInfo.zig");
const values = @import("values.zig");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const strings = @import("strings.zig");
const table = @import("table.zig");

const Allocator = std.mem.Allocator;

pub const ObjectFunction = struct {
    chunk: bci.Chunk = undefined, // 48bytes
    name: ?*const strings.ObjectString = undefined,
    arity: u8 = undefined,

    pub fn initInplace(self: *ObjectFunction, alloc: Allocator, gcAlloc: *memory.GCAllocator, name: ?*const strings.ObjectString, chunk: bci.Chunk, arity: u8) !void {
        const nameTrueSize = @as(usize, if (name) |n| n.length else 0);
        const chunkTrueSize = chunk.codeSlice.len * @sizeOf(u8) + chunk.constantSlice.len * @sizeOf(values.Value) + chunk.lineSlice.len * @sizeOf(usize);
        // Record true size of function
        try gcAlloc.addAllocation(.{ .Function = self }, nameTrueSize + chunkTrueSize, alloc);
        self.name = name;
        self.chunk = chunk;
        self.arity = arity;
        return;
    }

    pub fn createEmpty(alloc: Allocator, gcAlloc: *memory.GCAllocator) !*ObjectFunction {
        const funcPtr = try alloc.create(ObjectFunction);
        const funcObj = objects.Object{ .Function = funcPtr };
        // std.debug.print("funcPtr{}\n", .{funcPtr.object.kind});
        try gcAlloc.addAllocation(funcObj, @sizeOf(ObjectFunction), alloc);
        return funcPtr;
    }

    pub fn getName(self: *const ObjectFunction) []const u8 {
        if (self.name) |n| {
            return n.getString();
        } else return "<script>";
    }
};
