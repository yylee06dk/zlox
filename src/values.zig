const std = @import("std");
const objects = @import("objects.zig");
const strings = @import("strings.zig");

pub const valueType = enum {
    number,
    boolean,
    nil,
    obj,
};

pub const Value = union(valueType) {
    number: f64,
    boolean: bool,
    nil: u1,
    obj: *objects.Object,

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

    pub fn isObj(self: Value) bool {
        return switch (self) {
            .obj => true,
            else => false,
        };
    }

    pub fn asNum(self: Value) f64 {
        return self.number;
    }

    pub fn asBool(self: Value) bool {
        return self.boolean;
    }

    pub fn asObj(self: Value) *objects.Object {
        return self.obj;
    }

    fn typeToString(self: Value) []const u8 {
        return switch (self) {
            .boolean => "boolean",
            .number => "number",
            .nil => "nil",
            .obj => "object",
        };
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        try writer.print("[type: {s}, value: ", .{self.typeToString()});
        switch (self) {
            .boolean => try writer.print("{}]", .{self.boolean}),
            .number => try writer.print("{}]", .{self.number}),
            .nil => try writer.print("<nil>]", .{}),
            .obj => {
                const objStr: *strings.ObjectString = @ptrCast(@alignCast(self.obj));
                try writer.print("<obj:{}, {s}>]", .{ self.obj.kind, objStr.getString() });
            },
        }
    }
};
