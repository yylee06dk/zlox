const std = @import("std");
const _String = @import("object/string.zig").String;
const _Function = @import("object/function.zig").Function;
const _Closure = @import("object/closure.zig").Closure;
const _Upvalue = @import("object/upvalue.zig").Upvalue;

pub const ValueType = enum {
    Number,
    Boolean,
    Nil,
    String,
    Function,
    Closure,
    Upvalue,
};

pub const Value = union(ValueType) {
    Number: f64,
    Boolean: bool,
    Nil: u1,
    String: *StringObject,
    Function: *FunctionObject,
    Closure: *ClosureObject,
    Upvalue: *UpvalueObject,

    pub const StringObject = _String;
    pub const FunctionObject = _Function;
    pub const ClosureObject = _Closure;
    pub const UpvalueObject = _Upvalue;

    pub fn isNum(self: Value) bool {
        return switch (self) {
            .Number => true,
            else => false,
        };
    }

    pub fn isBool(self: Value) bool {
        return switch (self) {
            .Boolean => true,
            else => false,
        };
    }

    pub fn isNil(self: Value) bool {
        return switch (self) {
            .Nil => true,
            else => false,
        };
    }

    pub fn isObj(self: Value) bool {
        return switch (self) {
            .String, .Function, .Closure, .Upvalue => true,
            else => false,
        };
    }

    pub fn isString(self: Value) bool {
        return switch (self) {
            .String => true,
            else => false,
        };
    }

    pub fn isFunction(self: Value) bool {
        return switch (self) {
            .Function => true,
            else => false,
        };
    }

    pub fn isClosure(self: Value) bool {
        return switch (self) {
            .Closure => true,
            else => false,
        };
    }

    pub fn isUpvalue(self: Value) bool {
        return switch (self) {
            .Upvalue => true,
            else => false,
        };
    }

    pub fn asNum(self: Value) f64 {
        return self.Number;
    }

    pub fn asBool(self: Value) bool {
        return self.Boolean;
    }

    pub fn asString(self: Value) ?*StringObject {
        return switch (self) {
            .String => |string| string,
            else => null,
        };
    }

    pub fn asFunction(self: Value) ?*FunctionObject {
        return switch (self) {
            .Function => |function| function,
            else => null,
        };
    }

    pub fn asClosure(self: Value) ?*ClosureObject {
        return switch (self) {
            .Closure => |closure| closure,
            else => null,
        };
    }

    pub fn asUpvalue(self: Value) ?*UpvalueObject {
        return switch (self) {
            .Upvalue => |upvalue| upvalue,
            else => null,
        };
    }

    fn typeToString(self: Value) []const u8 {
        return switch (self) {
            .Boolean => "boolean",
            .Number => "number",
            .Nil => "nil",
            .String => "string",
            .Function => "function",
            .Closure => "closure",
            .Upvalue => "upvalue",
        };
    }

    pub fn formatDisplay(self: Value, writer: *std.Io.Writer) !void {
        switch (self) {
            .Boolean => |b| try writer.print("{}", .{b}),
            .Number => |n| try writer.print("{d}", .{n}),
            .Nil => try writer.print("<nil>", .{}),
            .String => |s| try writer.print("{s}", .{s.getString()}),
            .Function => |f| try writer.print("{f}", .{f.*}),
            .Closure => |c| try writer.print("{f}", .{c.*}),
            .Upvalue => |u| try writer.print("{f}", .{u.*}),
        }
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        try writer.print("[type: {s}, value: ", .{self.typeToString()});
        switch (self) {
            .Boolean => |b| try writer.print("{}]", .{b}),
            .Number => |n| try writer.print("{}]", .{n}),
            .Nil => try writer.print("<nil>]", .{}),
            .String => |s| {
                try writer.print("{s}]", .{s.getString()});
            },
            .Function => |f| try writer.print("{f}]", .{f.*}),
            .Closure => |c| try writer.print("{f}]", .{c.*}),
            .Upvalue => |u| try writer.print("{f}]", .{u.*}),
        }
    }
};
