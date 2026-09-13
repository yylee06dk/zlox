const std = @import("std");
const strings = @import("strings.zig");
const functions = @import("functions.zig");

pub const ObjectType = enum {
    String,
    Function,
};

pub const Object = union(ObjectType) {
    String: *strings.ObjectString,
    Function: *functions.ObjectFunction,

    pub fn isString(self: Object) bool {
        return switch (self) {
            .String => true,
            else => false,
        };
    }

    pub fn isFunction(self: Object) bool {
        return switch (self) {
            .Function => true,
            else => false,
        };
    }

    pub fn getPointer(self: Object) *anyopaque {
        return switch (self) {
            .String => |s| s,
            .Function => |f| f,
        };
    }

    pub fn getString(self: Object) []const u8 {
        std.debug.assert(std.meta.activeTag(self) == .String);
        const strPtr = self.String;
        return strPtr.getString();
    }

    pub fn getName(self: Object) []const u8 {
        std.debug.assert(std.meta.activeTag(self) == .Function);
        const funcPtr = self.Function;
        return funcPtr.getName();
    }
};
