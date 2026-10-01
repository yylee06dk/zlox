const std = @import("std");
const Value = @import("values.zig").Value;
const vm = @import("vm.zig");
const Allocator = std.mem.Allocator;

const print = std.debug.print;

pub const GarbageCollector = struct {
    allocationList: std.ArrayList(Allocation) = .empty,
    greyStack: std.ArrayList(*GCHeader) = .empty,
    curAllocSize: usize = 0,
    nextThreshold: usize = 1024 * 1024,
    traceGC: bool = false,
    stressGC: bool = false,

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
        if (self.stressGC or self.curAllocSize > self.nextThreshold) {
            try self.collectGarbage(alloc);
        }
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
                const strPtr = objectFromHeader(Value.StringObject, header);
                const objAsBytes: [*]u8 = @ptrCast(strPtr);
                const totalObject: []u8 = objAsBytes[0..size];
                // This cast is safe since every object comes from alignedAlloc
                const totalStringWithAlign = @as([]align(@alignOf(Value.StringObject)) u8, @alignCast(totalObject));
                alloc.free(totalStringWithAlign);
                self.curAllocSize -= size;
            },
            .Function => {
                const funcPtr = objectFromHeader(Value.FunctionObject, header);
                funcPtr.chunk.deinit(alloc);
                alloc.destroy(funcPtr);
                self.curAllocSize -= size;
            },
            .Closure => {
                const closurePtr = objectFromHeader(Value.ClosureObject, header);
                alloc.free(closurePtr.upvalueObjs);
                alloc.destroy(closurePtr);
                self.curAllocSize -= size;
            },
            .Upvalue => {
                const upvaluePtr = objectFromHeader(Value.UpvalueObject, header);
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

    // GC related function
    fn collectGarbage(self: *GarbageCollector, alloc: Allocator) !void {
        if (self.traceGC) print("---- GC bootup ----\n", .{});
        try self.markRoots(alloc);
        try self.traceReferences(alloc);
        try self.sweep(alloc);
        if (self.traceGC) print("---- GC Ended ----\n", .{});
    }

    fn markRoots(self: *GarbageCollector, alloc: Allocator) !void {
        const machine: *vm.VM = @fieldParentPtr("gcAlloc", self);
        // Mark stack-existent objects
        var idx: usize = 0;
        while (idx < machine.stack.length) : (idx += 1) {
            try self.markValue(machine.stack.stackArray[idx], alloc);
        }
        // Mark globals-existent objects
        idx = 0;
        while (idx < machine.globals.capacity) : (idx += 1) {
            const cur = machine.globals.baseArray[idx];
            if (cur) |entry| {
                try self.markObject(.{ .String = entry.key }, alloc);
                try self.markValue(entry.value, alloc);
            }
        }
        // Mark openUpvalues
        var cur = machine.openUpvalues;
        while (cur != null) {
            const c = cur orelse unreachable;
            try self.markObject(.{ .Upvalue = c }, alloc);
            cur = c.next;
        }

        // Mark call frame-living closures
        idx = 0;
        while (idx < machine.frameCount) : (idx += 1) {
            const closurePtr = machine.frames[idx].closure;
            try self.markObject(.{ .Closure = closurePtr }, alloc);
        }
    }

    fn markValue(self: *GarbageCollector, value: Value, alloc: Allocator) Allocator.Error!void {
        if (!value.isObj()) return;
        try self.markObject(value, alloc);
    }

    fn markObject(self: *GarbageCollector, value: Value, alloc: Allocator) Allocator.Error!void {
        // Add debugging logs
        if (self.traceGC) print("  marking: {f}\n", .{value});
        switch (std.meta.activeTag(value)) {
            .String => {
                const strPtr = value.String;
                if (strPtr.gcHeader.isMarked) return;
                strPtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &strPtr.gcHeader);
            },
            .Function => {
                const funcPtr = value.Function;
                if (funcPtr.gcHeader.isMarked) return;
                funcPtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &funcPtr.gcHeader);
            },
            .Closure => {
                const closurePtr = value.Closure;
                if (closurePtr.gcHeader.isMarked) return;
                closurePtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &closurePtr.gcHeader);
            },
            .Upvalue => {
                const upvaluePtr = value.Upvalue;
                if (upvaluePtr.gcHeader.isMarked) return;
                upvaluePtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &upvaluePtr.gcHeader);
            },
            .Number, .Boolean, .Nil => unreachable,
        }
    }

    fn traceReferences(self: *GarbageCollector, alloc: Allocator) !void {
        var current = self.greyStack.pop();
        while (current != null) : (current = self.greyStack.pop()) {
            const header = current orelse unreachable;

            try self.blackenObjectFromHeader(header, alloc);
        }
    }

    fn blackenObjectFromHeader(self: *GarbageCollector, header: *GCHeader, alloc: Allocator) !void {
        switch (header.kind) {
            .String => {},
            .Function => {
                const funcPtr = objectFromHeader(Value.FunctionObject, header);
                if (self.traceGC) print("  blackening {f}\n", .{funcPtr.*});
                // mark values in constantSlice
                var idx: usize = 0;
                while (idx < funcPtr.chunk.constantSlice.len) : (idx += 1) {
                    try self.markValue(funcPtr.chunk.constantSlice[idx], alloc);
                }
                if (funcPtr.name) |n| try self.markObject(.{ .String = n }, alloc);
            },
            .Closure => {
                const closurePtr = objectFromHeader(Value.ClosureObject, header);
                if (self.traceGC) print("  blackening {f}\n", .{closurePtr.*});
                try self.markObject(.{ .Function = closurePtr.baseFunction }, alloc);
                for (closurePtr.upvalueObjs) |upvalueObj| {
                    try self.markObject(.{ .Upvalue = upvalueObj }, alloc);
                }
            },
            .Upvalue => {
                const upvaluePtr = objectFromHeader(Value.UpvalueObject, header);
                if (self.traceGC) print("  blackening {f}\n", .{upvaluePtr.*});
                try self.markValue(upvaluePtr.value.*, alloc);
            },
        }
    }

    fn sweep(self: *GarbageCollector, alloc: Allocator) Allocator.Error!void {
        var newAllocList: std.ArrayList(Allocation) = .empty;
        for (self.allocationList.items) |item| {
            const header = item.payload;
            const size = item.size;
            if (header.isMarked) {
                newAllocList.append(alloc, item) catch unreachable; // Need a way to deal with OOM happening in such cases
            } else {
                self.freeObjectFromHeader(header, size, alloc);
            }
        }
        self.allocationList.deinit(alloc);
        self.allocationList = newAllocList;
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
                    const strPtr = objectFromHeader(Value.StringObject, header);
                    try writer.print("String: {s} | size: {d}\n", .{ strPtr.getString(), size });
                },
                .Function => {
                    const funcPtr = objectFromHeader(Value.FunctionObject, header);
                    try writer.print("Function: {f} | size: {d}\n", .{ funcPtr.*, size });
                },
                .Closure => {
                    const closurePtr = objectFromHeader(Value.ClosureObject, header);
                    try writer.print("Closure: {f} | size: {d}\n", .{ closurePtr.*, size });
                },
                .Upvalue => {
                    const upvaluePtr = objectFromHeader(Value.UpvalueObject, header);
                    try writer.print("Upvalue: {f} | size: {d}\n", .{ upvaluePtr.*, size });
                },
            }
        }
    }
};
