const std = @import("std");
const bci = @import("../bytecodeInfo.zig");
const String = @import("string.zig").String;

pub const Function = struct {
    chunk: bci.Chunk = undefined,
    name: ?*const String = undefined,
    arity: u8 = undefined,

    pub fn getName(self: *const Function) []const u8 {
        if (self.name) |name| {
            return name.getString();
        }
        return "<script>";
    }
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s}", .{self.getName()});
    }
};
