const std = @import("std");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const vmStack = @import("vmStack.zig");
const values = @import("values.zig");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const strings = @import("strings.zig");

const print = std.debug.print;
const t = std.debug.print;
const Allocator = std.mem.Allocator;

pub const VMError = error{
    CompileErr,
    RuntimeErr,
};

pub const VM = struct {
    byteCodeInfo: *const bcInfo.ByteCodeInfo = undefined, // Does not own the bcInfo struct
    ip: usize = 0,
    debugFlag: bool = false,
    stack: vmStack.Stack,
    gcAlloc: memory.GCAllocator = .{},

    pub fn initSettings(debugFlag: bool) VM {
        return .{
            .debugFlag = debugFlag,
            .stack = .{},
        };
    }

    pub fn deinit(self: *VM, alloc: Allocator) void {
        self.gcAlloc.freeAll(alloc);
        self.gcAlloc.deinit(alloc);
    }

    pub fn setByteCode(self: *VM, byteCodeInfo: *const bcInfo.ByteCodeInfo) void {
        self.byteCodeInfo = byteCodeInfo;
    }

    pub fn execute(self: *VM, writer: *std.Io.Writer, alloc: Allocator) !void {
        if (self.debugFlag) {
            try writer.print("==== VM Execute Trace ====\n", .{});
        }
        while (!self.isAtEnd()) {
            const curCode = self.advance();
            const opCode: bc.opCode = @enumFromInt(curCode);
            switch (opCode) {
                .ReturnOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | returned, peek: {?}\n", .{ self.ip - 1, self.stack.peek(0) });
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
                    const rPeek = self.stack.peek(0) orelse return VMError.CompileErr;
                    const lPeek = self.stack.peek(1) orelse return VMError.CompileErr;
                    const rNum = rPeek.isNum();
                    const lNum = lPeek.isNum();
                    const rStr = result: {
                        const rObj = if (rPeek.isObj()) rPeek.asObj() else break :result false;
                        break :result rObj.kind == objects.ObjectType.String;
                    };
                    const lStr = result: {
                        const lObj = if (lPeek.isObj()) lPeek.asObj() else break :result false;
                        break :result lObj.kind == objects.ObjectType.String;
                    };

                    if ((lNum and rNum) or (lStr and rStr)) {
                        const rValue = self.stack.pop() orelse return VMError.CompileErr;
                        const lValue = self.stack.pop() orelse return VMError.CompileErr;
                        if (lNum) { // Case of number addition
                            const result = lValue.asNum() + rValue.asNum();
                            if (self.debugFlag) {
                                try writer.print("{d}\n", .{result});
                            }
                            try self.stack.push(values.Value{ .number = result });
                        } else { // String concatenation
                            const lString = lValue.asObj().getString();
                            const rString = rValue.asObj().getString();
                            const concatString = try std.mem.concat(alloc, u8, &.{ lString, rString });
                            defer alloc.free(concatString);
                            const ptr = try strings.makeString(concatString, concatString.len, &self.gcAlloc, alloc);
                            if (self.debugFlag) {
                                try writer.print("{s}\n", .{ptr.getString()});
                            }
                            try self.stack.push(values.Value{ .obj = @ptrCast(ptr) });
                        }
                        continue;
                    }
                    return VMError.RuntimeErr;
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
                        try writer.print("{d:0>4} | mult: ", .{self.ip - 1});
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
                        try writer.print("{d:0>4} | div: ", .{self.ip - 1});
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
