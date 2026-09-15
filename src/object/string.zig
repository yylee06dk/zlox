const std = @import("std");

pub const String = struct {
    length: u32,
    hash: u32,

    // Characters trail the struct in the same allocation.
    pub fn getString(self: *const String) []const u8 {
        const selfAsBytes: [*]const u8 = @ptrCast(@alignCast(self));
        return selfAsBytes[@sizeOf(String)..][0..self.length];
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s}", .{self.getString()});
    }
};
