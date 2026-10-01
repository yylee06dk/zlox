const std = @import("std");
const bci = @import("bytecodeInfo.zig");
const Compiler = @import("compiler.zig").Compiler;
const GC = @import("memory.zig").GarbageCollector;
const table = @import("table.zig");
const Value = @import("values.zig").Value;
const vm = @import("vm.zig");

const Allocator = std.mem.Allocator;

// Just checks string pool
// NOTE: Need to check if all calls are safe with the guard for GC existing at allocate String.
pub fn makeString(start: []const u8, length: usize, gcAlloc: *GC, stringPool: *table.Table, compiler: ?*Compiler, alloc: Allocator) Allocator.Error!*Value.StringObject {
    const string = start[0..length];
    const hash = std.hash.Fnv1a_32.hash(string);

    if (stringPool.contains(string, hash)) |interned| {
        return interned;
    }

    const totalLength = @sizeOf(Value.StringObject) + length;
    return allocateString(totalLength, string, hash, gcAlloc, stringPool, compiler, alloc);
}

// Where actually strings are made.
// Does memory allocation
fn allocateString(totalLength: usize, string: []const u8, hash: u32, gcAlloc: *GC, stringPool: *table.Table, compiler: ?*Compiler, alloc: Allocator) Allocator.Error!*Value.StringObject {
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
    try gcAlloc.addAllocation(compiler, &strPtr.gcHeader, totalLength, alloc);
    strPtr.gcHeader.isMarked = false;
    _ = try stringPool.set(strPtr, .{ .Nil = 1 }, alloc);

    return strPtr;
}

pub fn createFunction(alloc: Allocator, gcAlloc: *GC, name: ?*Value.StringObject, chunk: bci.Chunk, arity: u8, upvalueCount: u8, compiler: ?*Compiler) !*Value.FunctionObject {
    const funcPtr = try alloc.create(Value.FunctionObject);
    errdefer alloc.destroy(funcPtr);
    funcPtr.gcHeader = .{
        .kind = GC.GCHeader.ObjKind.Function,
        .isMarked = false,
    };
    funcPtr.name = name;
    funcPtr.chunk = chunk;
    funcPtr.arity = arity;
    funcPtr.upvalueCount = upvalueCount;

    const chunkTrueSize = chunk.codeSlice.len * @sizeOf(u8) + std.mem.sliceAsBytes(chunk.constantSlice).len + chunk.lineSlice.len * @sizeOf(usize);
    const totalSize = @sizeOf(Value.FunctionObject) + chunkTrueSize;

    const machine: *vm.VM = @fieldParentPtr("gcAlloc", gcAlloc);
    try machine.stack.push(.{ .Function = funcPtr });
    try gcAlloc.addAllocation(compiler, &funcPtr.gcHeader, totalSize, alloc);
    _ = machine.stack.pop();

    return funcPtr;
}

pub fn createClosure(alloc: Allocator, gcAlloc: *GC, baseFunction: *Value.FunctionObject) !*Value.ClosureObject {
    var closurePtr = try alloc.create(Value.ClosureObject);
    closurePtr.gcHeader = .{
        .kind = GC.GCHeader.ObjKind.Closure,
        .isMarked = false,
    };
    errdefer alloc.destroy(closurePtr);
    closurePtr.baseFunction = baseFunction;
    closurePtr.upvalueObjs = try alloc.alloc(?*Value.UpvalueObject, baseFunction.upvalueCount);
    // Zero init
    var idx: usize = 0;
    while (idx < baseFunction.upvalueCount) : (idx += 1) {
        closurePtr.upvalueObjs[idx] = null;
    }

    const totalSize = @sizeOf(Value.ClosureObject) + @sizeOf(*Value.UpvalueObject) * baseFunction.upvalueCount;

    const machine: *vm.VM = @fieldParentPtr("gcAlloc", gcAlloc);
    try machine.stack.push(.{ .Closure = closurePtr });
    try gcAlloc.addAllocation(null, &closurePtr.gcHeader, totalSize, alloc);
    _ = machine.stack.pop();
    // init
    return closurePtr;
}

pub fn createUpvalue(alloc: Allocator, gcAlloc: *GC, location: *Value) !*Value.UpvalueObject {
    var upvaluePtr = try alloc.create(Value.UpvalueObject);
    errdefer alloc.destroy(upvaluePtr);
    upvaluePtr.* = .{ .gcHeader = .{
        .kind = .Upvalue,
        .isMarked = false,
    }, .value = location, .next = null };

    const machine: *vm.VM = @fieldParentPtr("gcAlloc", gcAlloc);
    try machine.stack.push(.{ .Upvalue = upvaluePtr });
    try gcAlloc.addAllocation(null, &upvaluePtr.gcHeader, @sizeOf(Value.UpvalueObject), alloc);
    _ = machine.stack.pop();
    return upvaluePtr;
}
