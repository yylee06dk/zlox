const strings = @import("strings.zig");

pub const ObjectType = enum {
    String,
};

pub const Object = struct {
    kind: ObjectType,

    pub fn isString(self: *Object) bool {
        return self.kind == .String;
    }

    pub fn getString(self: *Object) []const u8 {
        const strPtr: *strings.ObjectString = @ptrCast(@alignCast(self));
        return strPtr.getString();
    }
};
