const std = @import("std");
const values = @import("../values.zig");
const GC = @import("../memory.zig").GarbageCollector;

pub const Upvalue = struct {
    gcHeader: GC.GCHeader = undefined,
    value: *values.Value = undefined,
    closed: values.Value = undefined,
    next: ?*Upvalue = undefined,

    pub fn isClosed(self: *Upvalue) bool {
        const offset = @offsetOf(@This(), "closed");
        const startOfStruct = @intFromPtr(self);
        const posOfValue = @intFromPtr(self.value);

        return posOfValue - startOfStruct == offset;
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("upvalue: {f}", .{self.value.*});
    }
};
