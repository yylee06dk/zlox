const std = @import("std");
const bci = @import("../bytecodeInfo.zig");
const GC = @import("../memory.zig").GarbageCollector;
const String = @import("string.zig").String;

pub const Function = struct {
    gcHeader: GC.GCHeader = undefined,
    chunk: bci.Chunk = undefined,
    name: ?*const String = undefined,
    upvalueCount: u8 = undefined,
    arity: u8 = undefined,

    fn getName(self: *const Function) []const u8 {
        if (self.name) |name| {
            return name.getString();
        }
        return "_script_";
    }

    pub fn formatTotal(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{f}\n", .{self});
        try writer.print("BYTE | LINE | --------\n", .{});
        try self.chunk.printChunk(writer);
        try writer.print("\n", .{});
        try writer.flush();
    }
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("<fn {s}>", .{self.getName()});
    }
};
