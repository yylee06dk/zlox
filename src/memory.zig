const std = @import("std");
const objects = @import("objects.zig");
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
                .string => |s| {
                    const objAsBytes: [*]u8 = @ptrCast(s);
                    const totalObject: []u8 = objAsBytes[0..size];
                    // This cast is safe since every object comes from alignedAlloc
                    const totalObjectWithAlign = @as([]align(@alignOf(objects.Object.String)) u8, @alignCast(totalObject));
                    alloc.free(totalObjectWithAlign);
                },
                .function => |f| {
                    f.chunk.deinit(alloc);
                    alloc.destroy(f);
                },
                .closure => |c| {
                    alloc.free(c.upvalueObjs);
                    alloc.destroy(c);
                },
                .upvalue => |u| {
                    alloc.destroy(u);
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
                .string => |s| {
                    try writer.print("String: {s} | size: {d}\n", .{ s.getString(), size });
                },
                .function => |f| {
                    try writer.print("Function: {f} | size: {d}\n", .{ f.*, size });
                },
                .closure => |c| {
                    try writer.print("Closure: {f} | size: {d}\n", .{ c.*, size });
                },
                .upvalue => |u| {
                    try writer.print("Upvalue: {f} | size: {d}\n", .{ u.*, size });
                },
            }
        }
    }
};
