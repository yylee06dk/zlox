const std = @import("std");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const vmStack = @import("vmStack.zig");
const values = @import("values.zig");

const print = std.debug.print;
const t = std.debug.print;
const Allocator = std.mem.Allocator;

pub const VMError = error{
    CompileErr,
    RuntimeErr,
};

pub const VM = struct {
    byteCodeInfo: *const bcInfo.ByteCodeInfo, // Does not own the bcInfo struct
    ip: usize = 0,
    debugFlag: bool = false,
    stack: vmStack.Stack,

    pub fn init(source: *const bcInfo.ByteCodeInfo, debugFlag: bool) VM {
        return .{ .byteCodeInfo = source, .debugFlag = debugFlag, .stack = .{} };
    }

    pub fn execute(self: *VM, writer: *std.Io.Writer) !void {
        if (self.debugFlag) {
            try writer.print("==== VM Execute Trace ====\n", .{});
        }
        while (!self.isAtEnd()) {
            const curCode = self.advance();
            const opCode: bc.opCode = @enumFromInt(curCode);
            switch (opCode) {
                .ReturnOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | returned, peek: {?}\n", .{ self.ip - 1, self.stack.peek() });
                    }
                },
                .ConstantOp => {
                    try writer.print("{d:0>4} | constant: ", .{self.ip - 1});
                    const valueAddr = self.advance();
                    const value = self.byteCodeInfo.constantList.items[valueAddr];
                    try self.stack.push(value);
                    if (self.debugFlag) {
                        try writer.print("{}\n", .{value});
                    }
                },
                .NegateOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | negate: ", .{self.ip - 1});
                    }
                    const value = self.stack.pop();
                    if (value) |v| {
                        if (v.isNum()) {
                            if (self.debugFlag) {
                                try writer.print("{d} -> {d}\n", .{ v.asNum(), -v.asNum() });
                            }
                            try self.stack.push(values.Value{ .number = -v.asNum() });
                            continue;
                        }
                        return VMError.RuntimeErr;
                    } else {
                        return VMError.CompileErr;
                    }
                },
                .AddOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | add: ", .{self.ip - 1});
                    }
                    const rValue = self.stack.pop() orelse return VMError.CompileErr;
                    const lValue = self.stack.pop() orelse return VMError.CompileErr;
                    if (!lValue.isNum() or !rValue.isNum()) {
                        return VMError.RuntimeErr;
                    }

                    const result = lValue.asNum() + rValue.asNum();
                    if (self.debugFlag) {
                        try writer.print("{d}\n", .{result});
                    }
                    try self.stack.push(values.Value{ .number = result });
                },
                .SubOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | sub: ", .{self.ip - 1});
                    }
                    const rValue = self.stack.pop() orelse return VMError.CompileErr;
                    const lValue = self.stack.pop() orelse return VMError.CompileErr;
                    if (!lValue.isNum() or !rValue.isNum()) {
                        return VMError.RuntimeErr;
                    }

                    const result = lValue.asNum() - rValue.asNum();
                    if (self.debugFlag) {
                        try writer.print("{d}\n", .{result});
                    }
                    try self.stack.push(values.Value{ .number = result });
                },
                .MultOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | add: ", .{self.ip - 1});
                    }
                    const rValue = self.stack.pop() orelse return VMError.CompileErr;
                    const lValue = self.stack.pop() orelse return VMError.CompileErr;
                    if (!lValue.isNum() or !rValue.isNum()) {
                        return VMError.RuntimeErr;
                    }

                    const result = lValue.asNum() * rValue.asNum();
                    if (self.debugFlag) {
                        try writer.print("{d}\n", .{result});
                    }
                    try self.stack.push(values.Value{ .number = result });
                },
                .DivOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | add: ", .{self.ip - 1});
                    }
                    const rValue = self.stack.pop() orelse return VMError.CompileErr;
                    const lValue = self.stack.pop() orelse return VMError.CompileErr;
                    if (!lValue.isNum() or !rValue.isNum()) {
                        return VMError.RuntimeErr;
                    }

                    const result = lValue.asNum() / rValue.asNum();
                    if (self.debugFlag) {
                        try writer.print("{d}\n", .{result});
                    }
                    try self.stack.push(values.Value{ .number = result });
                },

                // else => return VMError.CompileErr,
            }
        }
    }

    fn isAtEnd(
        self: *const VM,
    ) bool {
        return (self.ip >= self.byteCodeInfo.byteCodeList.items.len);
    }

    fn advance(self: *VM) u8 {
        self.ip += 1;
        return self.byteCodeInfo.byteCodeList.items[self.ip - 1];
    }
};
