const std = @import("std");
const GC = @import("../memory.zig").GarbageCollector;
const Value = @import("../values.zig").Value;

pub const Native = struct {
    gcHeader: GC.GCHeader = undefined,
    nativeFn: NativeFn = undefined,
    arity: u8 = undefined,
    pub const NativeFn = *const fn (args: []const Value) Value;

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        _ = self;
        try writer.print("<native fn>", .{});
    }
};
