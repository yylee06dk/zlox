const std = @import("std");

pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: u1,

    pub fn isNum(self: Value) bool {
        return switch (self) {
            .number => true,
            else => false,
        };
    }

    pub fn isBool(self: Value) bool {
        return switch (self) {
            .boolean => true,
            else => false,
        };
    }

    pub fn isNil(self: Value) bool {
        return switch (self) {
            .nil => true,
            else => false,
        };
    }

    pub fn asNum(self: Value) f64 {
        return self.number;
    }

    pub fn asBool(self: Value) bool {
        return self.boolean;
    }

    fn typeToString(self: Value) []const u8 {
        return switch (self) {
            .boolean => "boolean",
            .number => "number",
            .nil => "nil",
        };
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        try writer.print("[type: {s}, value: ", .{self.typeToString()});
        switch (self) {
            .boolean => try writer.print("{}]", .{self.boolean}),
            .number => try writer.print("{}]", .{self.number}),
            .nil => try writer.print("<nil>]", .{}),
        }
    }
};
