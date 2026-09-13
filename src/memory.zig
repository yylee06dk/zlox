const std = @import("std");
const objects = @import("objects.zig");
const strings = @import("strings.zig");
const functions = @import("functions.zig");
const Allocator = std.mem.Allocator;

pub const GCAllocator = struct {
    allocationList: std.ArrayList(Allocation) = .empty,
    curAllocSize: usize = 0,

    const Allocation = struct {
        payload: objects.Object,
        size: usize,
    };

    pub fn deinit(self: *GCAllocator, alloc: Allocator) void {
        self.allocationList.deinit(alloc);
    }

    pub fn addAllocation(self: *GCAllocator, item: objects.Object, sizeChange: usize, alloc: Allocator) Allocator.Error!void {
        if (!self.contains(item)) {
            try self.allocationList.append(alloc, .{ .payload = item, .size = sizeChange });
        }
        self.curAllocSize += sizeChange;
        // Later on check if it got over the limit
    }

    pub fn freeAll(self: *GCAllocator, alloc: Allocator) void {
        for (self.allocationList.items) |item| {
            const allocation = item.payload;
            const size = item.size;
            switch (allocation) {
                .String => |s| {
                    const objAsBytes: [*]u8 = @ptrCast(s);
                    const totalObject: []u8 = objAsBytes[0..size];
                    // This cast is safe since every object comes from alignedAlloc
                    const totalObjectWithAlign = @as([]align(@alignOf(strings.ObjectString)) u8, @alignCast(totalObject));
                    alloc.free(totalObjectWithAlign);
                },
                .Function => |f| {
                    alloc.destroy(f);
                },
            }
        }

        self.allocationList.clearRetainingCapacity();
        self.curAllocSize = 0;
    }

    fn contains(self: *GCAllocator, item: objects.Object) bool {
        for (self.allocationList.items) |v| {
            const allocation = v.payload;
            if (allocation.getPointer() == item.getPointer()) {
                return true;
            }
        }
        return false;
    }

    // ------- Pretty printing
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        for (self.allocationList.items) |item| {
            const allocation = item.payload;
            const size = item.size;
            switch (allocation) {
                .String => |s| {
                    try writer.print("String: {s} | size: {d}\n", .{ s.getString(), size });
                },
                .Function => |f| {
                    try writer.print("Function: {s} | size: {d}\n", .{ f.getName(), size });
                },
            }
        }
    }
};
