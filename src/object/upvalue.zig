const std = @import("std");
const values = @import("../values.zig");

pub const Upvalue = struct {
    value: *values.Value,
    next: ?*Upvalue,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("upvalue: {f}", .{self.value.*});
    }
};
