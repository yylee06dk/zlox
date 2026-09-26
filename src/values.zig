const std = @import("std");
const objects = @import("objects.zig");

pub const valueType = enum {
    number,
    boolean,
    nil,
    string,
    function,
    closure,
    upvalue,
};

pub const Value = union(valueType) {
    number: f64,
    boolean: bool,
    nil: u1,
    string: *objects.Object.String,
    function: *objects.Object.Function,
    closure: *objects.Object.Closure,
    upvalue: *objects.Object.Upvalue,

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
            .string, .function, .closure => true,
            else => false,
        };
    }

    pub fn isString(self: Value) bool {
        return switch (self) {
            .string => true,
            else => false,
        };
    }

    pub fn isFunction(self: Value) bool {
        return switch (self) {
            .function => true,
            else => false,
        };
    }

    pub fn isClosure(self: Value) bool {
        return switch (self) {
            .closure => true,
            else => false,
        };
    }

    pub fn isUpvalue(self: Value) bool {
        return switch (self) {
            .upvalue => true,
            else => false,
        };
    }

    pub fn asNum(self: Value) f64 {
        return self.number;
    }

    pub fn asBool(self: Value) bool {
        return self.boolean;
    }

    pub fn asString(self: Value) ?*objects.Object.String {
        return switch (self) {
            .string => |string| string,
            else => null,
        };
    }

    pub fn asFunction(self: Value) ?*objects.Object.Function {
        return switch (self) {
            .function => |function| function,
            else => null,
        };
    }

    pub fn asClosure(self: Value) ?*objects.Object.Closure {
        return switch (self) {
            .closure => |closure| closure,
            else => null,
        };
    }

    pub fn asUpvalue(self: Value) ?*objects.Object.Upvalue {
        return switch (self) {
            .upvalue => |upvalue| upvalue,
            else => null,
        };
    }

    fn typeToString(self: Value) []const u8 {
        return switch (self) {
            .boolean => "boolean",
            .number => "number",
            .nil => "nil",
            .string => "string",
            .function => "function",
            .closure => "closure",
            .upvalue => "upvalue",
        };
    }

    pub fn formatDisplay(self: Value, writer: *std.Io.Writer) !void {
        switch (self) {
            .boolean => |b| try writer.print("{}", .{b}),
            .number => |n| try writer.print("{d}", .{n}),
            .nil => try writer.print("<nil>", .{}),
            .string => |s| try writer.print("{s}", .{s.getString()}),
            .function => |f| try writer.print("{f}", .{f.*}),
            .closure => |c| try writer.print("{f}", .{c.*}),
            .upvalue => |u| try writer.print("{f}", .{u.*}),
        }
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        try writer.print("[type: {s}, value: ", .{self.typeToString()});
        switch (self) {
            .boolean => |b| try writer.print("{}]", .{b}),
            .number => |n| try writer.print("{}]", .{n}),
            .nil => try writer.print("<nil>]", .{}),
            .string => |s| {
                try writer.print("{s}]", .{s.getString()});
            },
            .function => |f| try writer.print("{f}]", .{f.*}),
            .closure => |c| try writer.print("{f}]", .{c.*}),
            .upvalue => |u| try writer.print("{f}]", .{u.*}),
        }
    }
};
