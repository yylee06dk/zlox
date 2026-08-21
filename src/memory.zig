const std = @import("std");
const objects = @import("objects.zig");
const Allocator = std.mem.Allocator;

pub const GCAllocator = struct {
    allocationList: std.ArrayList(*objects.Object) = .empty,
    curAllocSize: usize = 0,

    pub fn deinit(self: *GCAllocator, alloc: Allocator) void {
        self.allocationList.deinit(alloc);
    }

    pub fn addAllocation(self: *GCAllocator, itemPtr: *objects.Object, sizeChange: usize, alloc: Allocator) !void {
        try self.allocationList.append(alloc, itemPtr);
        self.curAllocSize += sizeChange;
        // Later on check if it got over the limit
    }
};
