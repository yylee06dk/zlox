const std = @import("std");
const bci = @import("../bytecodeInfo.zig");
const String = @import("string.zig").String;
const Function = @import("function.zig").Function;
const Upvalue = @import("upvalue.zig").Upvalue;

pub const Closure = struct {
    baseFunction: *Function,
    upvalueObjs: []*Upvalue,

    fn getName(self: *const Closure) []const u8 {
        if (self.baseFunction.name) |name| {
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
        try writer.print("<closure {s}>", .{self.getName()});
    }
};
