const std = @import("std");
const values = @import("values.zig");
const StackMax = 512;

pub const StackError = error{
    StackOverflow,
};

pub const Stack = struct {
    stackArray: [StackMax]values.Value = .{values.Value{ .nil = 1 }} ** StackMax, // I could use arrayLists but I wanted to have a maximum for it
    length: usize = 0,

    pub fn push(self: *Stack, item: values.Value) !void {
        if (self.length + 1 >= StackMax) {
            return StackError.StackOverflow;
        }

        self.stackArray[self.length] = item;
        self.length += 1;
    }

    pub fn pop(self: *Stack) ?values.Value {
        if (self.length == 0) {
            return null;
        }
        self.length -= 1;
        return self.stackArray[self.length];
    }

    pub fn peek(self: *const Stack, depth: usize) ?values.Value {
        if (self.length <= depth) {
            return null;
        }
        return self.stackArray[self.length - 1 - depth];
    }
};
