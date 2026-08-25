const std = @import("std");
const objects = @import("objects.zig");
const strings = @import("strings.zig");
const Allocator = std.mem.Allocator;

pub const Allocation = struct {
    payload: *objects.Object,
    size: usize,
};

pub const GCAllocator = struct {
    allocationList: std.ArrayList(Allocation) = .empty,
    curAllocSize: usize = 0,

    pub fn deinit(self: *GCAllocator, alloc: Allocator) void {
        self.allocationList.deinit(alloc);
    }

    pub fn addAllocation(self: *GCAllocator, itemPtr: *objects.Object, sizeChange: usize, alloc: Allocator) Allocator.Error!void {
        try self.allocationList.append(alloc, .{ .payload = itemPtr, .size = sizeChange });
        self.curAllocSize += sizeChange;
        // Later on check if it got over the limit
    }

    pub fn freeAll(self: *GCAllocator, alloc: Allocator) void {
        for (self.allocationList.items) |item| {
            const allocation = item.payload;
            const size = item.size;
            switch (allocation.kind) {
                .String => {
                    const objAsBytes: [*]u8 = @ptrCast(@alignCast(allocation));
                    const totalObject: []u8 = objAsBytes[0..size];
                    // This cast is safe since every object comes from alignedAlloc
                    const totalObjectWithAlign = @as([]align(@alignOf(strings.ObjectString)) u8, @alignCast(totalObject));
                    alloc.free(totalObjectWithAlign);
                },
            }
        }

        self.allocationList.clearRetainingCapacity();
        self.curAllocSize = 0;
    }

    // ------- Pretty printing
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        for (self.allocationList.items) |item| {
            const allocation = item.payload;
            const size = item.size;
            switch (allocation.kind) {
                .String => {
                    const objString: *strings.ObjectString = @ptrCast(@alignCast(allocation));
                    try writer.print("String: {s} | size: {d}\n", .{ objString.getString(), size });
                },
            }
        }
    }
};
