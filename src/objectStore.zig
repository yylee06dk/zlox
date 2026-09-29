const std = @import("std");
const bci = @import("bytecodeInfo.zig");
const GC = @import("memory.zig").GarbageCollector;
const table = @import("table.zig");
const Value = @import("values.zig").Value;

const Allocator = std.mem.Allocator;

// Just checks string pool
// NOTE: Need to check if all calls are safe with the guard for GC existing at allocate String.
pub fn makeString(start: []const u8, length: usize, gcAlloc: *GC, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*Value.String {
    const string = start[0..length];
    const hash = std.hash.Fnv1a_32.hash(string);

    if (stringPool.contains(string, hash)) |interned| {
        return interned;
    }

    const totalLength = @sizeOf(Value.String) + length;
    return allocateString(totalLength, string, hash, gcAlloc, stringPool, alloc);
}

// Where actually strings are made.
// Does memory allocation
fn allocateString(totalLength: usize, string: []const u8, hash: u32, gcAlloc: *GC, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*Value.String {
    const allocation = try alloc.alignedAlloc(u8, .of(Value.String), totalLength);
    errdefer alloc.free(allocation);

    const strPtr: *Value.String = @ptrCast(allocation);
    strPtr.* = .{
        .gcHeader = .{
            .kind = GC.GCHeader.ObjKind.String,
            .isMarked = true, // Keep it black(marked) while initializing
        },
        .length = @intCast(totalLength - @sizeOf(Value.String)),
        .hash = hash,
    };

    @memcpy(allocation[@sizeOf(Value.String)..], string);

    // Now the GC initializes it!
    try gcAlloc.addAllocation(&strPtr.gcHeader, totalLength, alloc);
    strPtr.gcHeader.isMarked = false;
    _ = try stringPool.set(strPtr, .{ .nil = 1 }, alloc);

    return strPtr;
}

pub fn createEmptyFunction(alloc: Allocator, gcAlloc: *GC) Allocator.Error!*Value.Function {
    const funcPtr = try alloc.create(Value.Function);
    funcPtr.gcHeader = .{
        .kind = GC.GCHeader.ObjKind.Function,
        .isMarked = true, // Keep black while init
    };
    errdefer alloc.destroy(funcPtr);

    try gcAlloc.addAllocation(&funcPtr.gcHeader, @sizeOf(Value.Function), alloc);
    funcPtr.gcHeader.isMarked = false;
    return funcPtr;
}

pub fn initFunctionInplace(self: *Value.Function, alloc: Allocator, gcAlloc: *GC, name: ?*const Value.String, chunk: bci.Chunk, arity: u8, upvalueCount: u8) Allocator.Error!void {
    const chunkTrueSize = chunk.codeSlice.len * @sizeOf(u8) + std.mem.sliceAsBytes(chunk.constantSlice).len + chunk.lineSlice.len * @sizeOf(usize);

    // Keep it safe while init
    self.gcHeader.isMarked = true;
    try gcAlloc.addAllocation(&self.gcHeader, chunkTrueSize, alloc);
    self.gcHeader.isMarked = false;
    self.name = name;
    self.chunk = chunk;
    self.arity = arity;
    self.upvalueCount = upvalueCount;
}

pub fn createClosure(alloc: Allocator, gcAlloc: *GC, baseFunction: *Value.Function) Allocator.Error!*Value.Closure {
    var closurePtr = try alloc.create(Value.Closure);
    closurePtr.gcHeader = .{
        .kind = GC.GCHeader.ObjKind.Closure,
        .isMarked = true,
    };
    errdefer alloc.destroy(closurePtr);

    try gcAlloc.addAllocation(&closurePtr.gcHeader, @sizeOf(Value.Closure), alloc);
    // init
    closurePtr.baseFunction = baseFunction;
    closurePtr.upvalueObjs = try alloc.alloc(*Value.Upvalue, baseFunction.upvalueCount);
    try gcAlloc.addAllocation(&closurePtr.gcHeader, @sizeOf(*Value.Upvalue) * @as(usize, baseFunction.upvalueCount), alloc);
    closurePtr.gcHeader.isMarked = false;
    return closurePtr;
}

pub fn createUpvalue(alloc: Allocator, gcAlloc: *GC, location: *Value) Allocator.Error!*Value.Upvalue {
    var upvaluePtr = try alloc.create(Value.Upvalue);
    upvaluePtr.gcHeader = .{
        .kind = .Upvalue,
        .isMarked = true,
    };
    errdefer alloc.destroy(upvaluePtr);

    try gcAlloc.addAllocation(&upvaluePtr.gcHeader, @sizeOf(Value.Upvalue), alloc);
    upvaluePtr.gcHeader.isMarked = false;
    upvaluePtr.value = location;
    upvaluePtr.next = null;
    return upvaluePtr;
}
