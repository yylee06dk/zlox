const std = @import("std");
const bci = @import("bytecodeInfo.zig");
const GC = @import("memory.zig").GarbageCollector;
const table = @import("table.zig");
const Value = @import("values.zig").Value;

const Allocator = std.mem.Allocator;

// Just checks string pool
// NOTE: Need to check if all calls are safe with the guard for GC existing at allocate String.
pub fn makeString(start: []const u8, length: usize, gcAlloc: *GC, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*Value.StringObject {
    const string = start[0..length];
    const hash = std.hash.Fnv1a_32.hash(string);

    if (stringPool.contains(string, hash)) |interned| {
        return interned;
    }

    const totalLength = @sizeOf(Value.StringObject) + length;
    return allocateString(totalLength, string, hash, gcAlloc, stringPool, alloc);
}

// Where actually strings are made.
// Does memory allocation
fn allocateString(totalLength: usize, string: []const u8, hash: u32, gcAlloc: *GC, stringPool: *table.Table, alloc: Allocator) Allocator.Error!*Value.StringObject {
    const allocation = try alloc.alignedAlloc(u8, .of(Value.StringObject), totalLength);
    errdefer alloc.free(allocation);

    const strPtr: *Value.StringObject = @ptrCast(allocation);
    strPtr.* = .{
        .gcHeader = .{
            .kind = GC.GCHeader.ObjKind.String,
            .isMarked = true, // Keep it black(marked) while initializing
        },
        .length = @intCast(totalLength - @sizeOf(Value.StringObject)),
        .hash = hash,
    };

    @memcpy(allocation[@sizeOf(Value.StringObject)..], string);

    // Now the GC initializes it!
    try gcAlloc.addAllocation(&strPtr.gcHeader, totalLength, alloc);
    strPtr.gcHeader.isMarked = false;
    _ = try stringPool.set(strPtr, .{ .Nil = 1 }, alloc);

    return strPtr;
}

pub fn createEmptyFunction(alloc: Allocator, gcAlloc: *GC) Allocator.Error!*Value.FunctionObject {
    const funcPtr = try alloc.create(Value.FunctionObject);
    funcPtr.gcHeader = .{
        .kind = GC.GCHeader.ObjKind.Function,
        .isMarked = true, // Keep black while init
    };
    errdefer alloc.destroy(funcPtr);

    try gcAlloc.addAllocation(&funcPtr.gcHeader, @sizeOf(Value.FunctionObject), alloc);
    funcPtr.gcHeader.isMarked = false;
    return funcPtr;
}

pub fn initFunctionInplace(self: *Value.FunctionObject, alloc: Allocator, gcAlloc: *GC, name: ?*const Value.StringObject, chunk: bci.Chunk, arity: u8, upvalueCount: u8) Allocator.Error!void {
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

pub fn createClosure(alloc: Allocator, gcAlloc: *GC, baseFunction: *Value.FunctionObject) Allocator.Error!*Value.ClosureObject {
    var closurePtr = try alloc.create(Value.ClosureObject);
    closurePtr.gcHeader = .{
        .kind = GC.GCHeader.ObjKind.Closure,
        .isMarked = true,
    };
    errdefer alloc.destroy(closurePtr);

    try gcAlloc.addAllocation(&closurePtr.gcHeader, @sizeOf(Value.ClosureObject), alloc);
    // init
    closurePtr.baseFunction = baseFunction;
    closurePtr.upvalueObjs = try alloc.alloc(*Value.UpvalueObject, baseFunction.upvalueCount);
    try gcAlloc.addAllocation(&closurePtr.gcHeader, @sizeOf(*Value.UpvalueObject) * @as(usize, baseFunction.upvalueCount), alloc);
    closurePtr.gcHeader.isMarked = false;
    return closurePtr;
}

pub fn createUpvalue(alloc: Allocator, gcAlloc: *GC, location: *Value) Allocator.Error!*Value.UpvalueObject {
    var upvaluePtr = try alloc.create(Value.UpvalueObject);
    upvaluePtr.gcHeader = .{
        .kind = .Upvalue,
        .isMarked = true,
    };
    errdefer alloc.destroy(upvaluePtr);

    try gcAlloc.addAllocation(&upvaluePtr.gcHeader, @sizeOf(Value.UpvalueObject), alloc);
    upvaluePtr.gcHeader.isMarked = false;
    upvaluePtr.value = location;
    upvaluePtr.closed = null;
    upvaluePtr.next = null;
    return upvaluePtr;
}
