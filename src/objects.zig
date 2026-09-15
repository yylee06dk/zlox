const std = @import("std");
const StringObject = @import("object/string.zig").String;
const FunctionObject = @import("object/function.zig").Function;

pub const ObjectType = enum {
    string,
    function,
};

// This is now like a fat pointer. -- normally shouldn't see types like *Object
pub const Object = union(ObjectType) {
    string: *String,
    function: *Function,

    pub const String = StringObject;
    pub const Function = FunctionObject;

    pub fn isString(self: Object) bool {
        return switch (self) {
            .string => true,
            else => false,
        };
    }

    pub fn isFunction(self: Object) bool {
        return switch (self) {
            .function => true,
            else => false,
        };
    }

    pub fn getPointer(self: Object) *anyopaque {
        return switch (self) {
            .string => |s| s,
            .function => |f| f,
        };
    }

    pub fn getString(self: Object) []const u8 {
        std.debug.assert(std.meta.activeTag(self) == .string);
        const strPtr = self.string;
        return strPtr.getString();
    }

    pub fn getName(self: Object) []const u8 {
        std.debug.assert(std.meta.activeTag(self) == .function);
        const funcPtr = self.function;
        return funcPtr.getName();
    }

    // --- Pretty Printing

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .string => |string| try writer.print("{s}", .{string.getString()}),
            .function => |function| try writer.print("{s}", .{function.getName()}),
        }
    }
};
