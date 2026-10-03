const std = @import("std");
const Value = @import("values.zig").Value;
const Compiler = @import("compiler.zig").Compiler;
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

        pub fn format(self: *@This(), writer: *std.Io.Writer) !void {
            switch (self.kind) {
                .String => {
                    const strPtr = objectFromHeader(Value.StringObject, self);
                    try writer.print("{*} -> {s}", .{ strPtr, strPtr.getString() });
                },
                .Function => {
                    const funcPtr = objectFromHeader(Value.FunctionObject, self);
                    try writer.print("{*} -> {f}", .{ funcPtr, funcPtr.* });
                },
                .Closure => {
                    const closurePtr = objectFromHeader(Value.ClosureObject, self);
                    try writer.print("{*} -> {f}", .{ closurePtr, closurePtr.* });
                },
                .Upvalue => {
                    const upvaluePtr = objectFromHeader(Value.UpvalueObject, self);
                    try writer.print("{*} -> {f}", .{ upvaluePtr, upvaluePtr.* });
                },
            }
        }
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

    pub fn addAllocation(self: *GarbageCollector, compiler: ?*Compiler, item: *GCHeader, sizeChange: usize, alloc: Allocator) Allocator.Error!void {
        if (!self.contains(item)) {
            try self.allocationList.append(alloc, .{ .payload = item, .size = sizeChange });
        }
        self.curAllocSize += sizeChange;
        // Later on check if it got over the limit
        if (self.stressGC or self.curAllocSize > self.nextThreshold) {
            try self.collectGarbage(compiler, alloc);
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
    fn collectGarbage(self: *GarbageCollector, compiler: ?*Compiler, alloc: Allocator) !void {
        if (self.traceGC) {
            const isCompiler = if (compiler) |_| "Compiler" else "VM";
            print("\n\n---- GC bootup from {s} ----\n", .{isCompiler});
        }
        try self.markRoots(compiler, alloc);
        try self.traceReferences(alloc);
        try self.sweep(alloc);
        if (self.traceGC) print("---- GC Ended ----\n", .{});
        self.nextThreshold = self.curAllocSize * 2;
        if (self.traceGC) {
            print("GC AfterMath: nextThreshold: {d}bytes, curAlloc: {d}bytes\n", .{ self.nextThreshold, self.curAllocSize });
            print("    {f}", .{self.*});
            print("\n---- ---- ----\n\n\n\n", .{});
        }
    }

    fn markRoots(self: *GarbageCollector, compiler: ?*Compiler, alloc: Allocator) !void {
        if (self.traceGC) print("---- Marking Roots ----\n", .{});
        const machine: *vm.VM = @fieldParentPtr("gcAlloc", self);
        if (self.traceGC) print("  ---- Marking VM Stack ----\n", .{});
        // Mark stack-existent objects
        var idx: usize = 0;
        while (idx < machine.stack.length) : (idx += 1) {
            try self.markValue(machine.stack.stackArray[idx], alloc);
        }
        if (self.traceGC) print("\n  ---- Marking globals ----\n", .{});
        // Mark globals-existent objects
        idx = 0;
        while (idx < machine.globals.capacity) : (idx += 1) {
            const cur = machine.globals.baseArray[idx];
            if (cur) |entry| {
                try self.markObject(.{ .String = entry.key }, alloc);
                try self.markValue(entry.value, alloc);
            }
        }
        if (self.traceGC) print("\n  ---- Marking open upvalues ----\n", .{});
        // Mark openUpvalues
        var cur = machine.openUpvalues;
        while (cur != null) {
            const c = cur orelse unreachable;
            try self.markObject(.{ .Upvalue = c }, alloc);
            cur = c.next;
        }

        if (self.traceGC) print("\n  ---- Marking call frame closures ----\n", .{});
        // Mark call frame-living closures
        idx = 0;
        while (idx < machine.frameCount) : (idx += 1) {
            const closurePtr = machine.frames[idx].closure;
            try self.markObject(.{ .Closure = closurePtr }, alloc);
        }

        if (self.traceGC) print("\n  ---- (Optional)Marking compiler roots ----\n", .{});
        if (compiler) |c| try c.markCompilerRoots(self, alloc);
        if (self.traceGC) print("---- Marking Roots Done ----\n", .{});
    }

    pub fn markValue(self: *GarbageCollector, value: Value, alloc: Allocator) Allocator.Error!void {
        if (!value.isObj()) return;
        try self.markObject(value, alloc);
    }

    pub fn markObject(self: *GarbageCollector, value: Value, alloc: Allocator) Allocator.Error!void {
        var header: *GCHeader = undefined;
        // Add debugging logs
        switch (std.meta.activeTag(value)) {
            .String => {
                const strPtr = value.String;
                header = &strPtr.gcHeader;
                if (strPtr.gcHeader.isMarked) return;
                strPtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &strPtr.gcHeader);
            },
            .Function => {
                const funcPtr = value.Function;
                header = &funcPtr.gcHeader;
                if (funcPtr.gcHeader.isMarked) return;
                funcPtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &funcPtr.gcHeader);
            },
            .Closure => {
                const closurePtr = value.Closure;
                header = &closurePtr.gcHeader;
                if (closurePtr.gcHeader.isMarked) return;
                closurePtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &closurePtr.gcHeader);
            },
            .Upvalue => {
                const upvaluePtr = value.Upvalue;
                header = &upvaluePtr.gcHeader;
                if (upvaluePtr.gcHeader.isMarked) return;
                upvaluePtr.gcHeader.isMarked = true;
                try self.greyStack.append(alloc, &upvaluePtr.gcHeader);
            },
            .Number, .Boolean, .Nil => unreachable,
        }
        if (self.traceGC) print("    mark: {f}\n", .{header});
    }

    fn traceReferences(self: *GarbageCollector, alloc: Allocator) !void {
        var current = self.greyStack.pop();
        while (current != null) : (current = self.greyStack.pop()) {
            const header = current orelse unreachable;

            try self.blackenObjectFromHeader(header, alloc);
        }
    }

    fn blackenObjectFromHeader(self: *GarbageCollector, header: *GCHeader, alloc: Allocator) !void {
        if (self.traceGC) print("    blacken: {f}\n", .{header});
        switch (header.kind) {
            .String => {},
            .Function => {
                const funcPtr = objectFromHeader(Value.FunctionObject, header);
                // mark values in constantSlice
                var idx: usize = 0;
                while (idx < funcPtr.chunk.constantSlice.len) : (idx += 1) {
                    try self.markValue(funcPtr.chunk.constantSlice[idx], alloc);
                }
                if (funcPtr.name) |n| try self.markObject(.{ .String = n }, alloc);
            },
            .Closure => {
                const closurePtr = objectFromHeader(Value.ClosureObject, header);
                try self.markObject(.{ .Function = closurePtr.baseFunction }, alloc);
                for (closurePtr.upvalueObjs) |upvalueObj| {
                    if (upvalueObj) |u| try self.markObject(.{ .Upvalue = u }, alloc);
                }
            },
            .Upvalue => {
                const upvaluePtr = objectFromHeader(Value.UpvalueObject, header);
                try self.markValue(upvaluePtr.value.*, alloc);
            },
        }
    }

    fn sweep(self: *GarbageCollector, alloc: Allocator) Allocator.Error!void {
        if (self.traceGC) print("---- Sweep started ----\n", .{});
        var newAllocList: std.ArrayList(Allocation) = .empty;
        for (self.allocationList.items) |item| {
            const header = item.payload;
            const size = item.size;
            if (header.isMarked) {
                item.payload.isMarked = false;
                newAllocList.append(alloc, item) catch unreachable; // Need a way to deal with OOM happening in such cases
            } else {
                if (self.traceGC) print("\x1b[91m    free: {f}\x1b[0m\n", .{header});
                self.freeObjectFromHeader(header, size, alloc);
            }
        }
        self.allocationList.deinit(alloc);
        self.allocationList = newAllocList;
        if (self.traceGC) print("---- Sweep ended ----\n", .{});
    }

    // ------- Pretty printing
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        for (self.allocationList.items) |item| {
            const header = item.payload;
            const size = item.size;
            try writer.print("{f} | size: {d}\n", .{ header, size });
        }
    }
};
