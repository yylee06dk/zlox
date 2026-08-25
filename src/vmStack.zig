const std = @import("std");
const values = @import("values.zig");

const Allocator = std.mem.Allocator;
const StackMax = 512;

pub const StackError = error{
    StackOverflow,
};

pub const Stack = struct {
    stackArray: []values.Value, // I could use arrayLists but I wanted to have a maximum for it
    length: usize = 0,

    pub fn init(alloc: Allocator) Allocator.Error!Stack {
        const slice = try alloc.alloc(values.Value, StackMax);
        return .{
            .stackArray = slice,
            .length = 0,
        };
    }

    pub fn deinit(self: *Stack, alloc: Allocator) void {
        alloc.free(self.stackArray);
    }

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

    pub fn clear(self: *Stack) void {
        self.length = 0;
    }
};
