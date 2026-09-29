const std = @import("std");
const Value = @import("values.zig").Value;
const Allocator = std.mem.Allocator;

pub const GarbageCollector = struct {
    allocationList: std.ArrayList(Allocation) = .empty,
    greyStack: std.ArrayList(*GCHeader) = .empty,
    curAllocSize: usize = 0,

    pub const GCHeader = struct {
        kind: ObjKind,
        isMarked: bool = false,

        pub const ObjKind = enum {
            String,
            Function,
            Closure,
            Upvalue,
        };
    };

    fn objectFromHeader(comptime T: type, header: *GCHeader) *T {
        return @alignCast(@fieldParentPtr("gcHeader", header));
    }

    const Allocation = struct {
        payload: *GCHeader,
        size: usize,
    };

    pub fn deinit(self: *GarbageCollector, alloc: Allocator) void {
        self.allocationList.deinit(alloc);
        self.greyStack.deinit(alloc);
    }

    pub fn addAllocation(self: *GarbageCollector, item: *GCHeader, sizeChange: usize, alloc: Allocator) Allocator.Error!void {
        if (!self.contains(item)) {
            try self.allocationList.append(alloc, .{ .payload = item, .size = sizeChange });
        }
        self.curAllocSize += sizeChange;
        // Later on check if it got over the limit
    }

    pub fn freeAll(self: *GarbageCollector, alloc: Allocator) void {
        for (self.allocationList.items) |item| {
            const header = item.payload;
            const size = item.size;
            self.freeObjectFromHeader(header, size, alloc);
        }

        self.allocationList.clearRetainingCapacity();
        self.curAllocSize = 0;
    }

    fn freeObjectFromHeader(self: *GarbageCollector, header: *GCHeader, size: usize, alloc: Allocator) void {
        switch (header.kind) {
            .String => {
                const strPtr = objectFromHeader(Value.String, header);
                const objAsBytes: [*]u8 = @ptrCast(strPtr);
                const totalObject: []u8 = objAsBytes[0..size];
                // This cast is safe since every object comes from alignedAlloc
                const totalStringWithAlign = @as([]align(@alignOf(Value.String)) u8, @alignCast(totalObject));
                alloc.free(totalStringWithAlign);
                self.curAllocSize -= size;
            },
            .Function => {
                const funcPtr = objectFromHeader(Value.Function, header);
                funcPtr.chunk.deinit(alloc);
                alloc.destroy(funcPtr);
                self.curAllocSize -= size;
            },
            .Closure => {
                const closurePtr = objectFromHeader(Value.Closure, header);
                alloc.free(closurePtr.upvalueObjs);
                alloc.destroy(closurePtr);
                self.curAllocSize -= size;
            },
            .Upvalue => {
                const upvaluePtr = objectFromHeader(Value.Upvalue, header);
                alloc.destroy(upvaluePtr);
                self.curAllocSize -= size;
            },
        }
    }

    fn contains(self: *GarbageCollector, targetHeader: *GCHeader) bool {
        for (self.allocationList.items) |v| {
            if (v.payload == targetHeader) return true;
        }
        return false;
    }

    // ------- Pretty printing
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        for (self.allocationList.items) |item| {
            const header = item.payload;
            const size = item.size;
            switch (header.kind) {
                .String => {
                    const strPtr = objectFromHeader(Value.String, header);
                    try writer.print("String: {s} | size: {d}\n", .{ strPtr.getString(), size });
                },
                .Function => {
                    const funcPtr = objectFromHeader(Value.Function, header);
                    try writer.print("Function: {f} | size: {d}\n", .{ funcPtr.*, size });
                },
                .Closure => {
                    const closurePtr = objectFromHeader(Value.Closure, header);
                    try writer.print("Closure: {f} | size: {d}\n", .{ closurePtr.*, size });
                },
                .Upvalue => {
                    const upvaluePtr = objectFromHeader(Value.Upvalue, header);
                    try writer.print("Upvalue: {f} | size: {d}\n", .{ upvaluePtr.*, size });
                },
            }
        }
    }
};
