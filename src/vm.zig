const std = @import("std");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const vmStack = @import("vmStack.zig");
const values = @import("values.zig");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const strings = @import("strings.zig");
const table = @import("table.zig");

const print = std.debug.print;
const t = std.debug.print;
const Allocator = std.mem.Allocator;

pub const VM = struct {
    chunk: *const bcInfo.Chunk = undefined, // Borrowed
    ip: usize = 0,
    debugFlag: bool = false,
    stack: vmStack.Stack,
    stringPool: table.Table,
    globals: table.Table,
    gcAlloc: memory.GCAllocator = .{},

    pub const Error = error{
        CompileError,
        RuntimeError,
    };

    pub const Diagnostic = struct {
        vmSnapShot: *VM = undefined,
        message: []const u8 = undefined,

        fn setContext(self: *Diagnostic, vm: *VM, message: []const u8) void {
            self.vmSnapShot = vm;
            self.message = message;
        }

        pub fn report(self: *Diagnostic) void {
            print("zlox: RuntimeError: [line:{d:>3}|ip:{d:0>4}] {s}\n", .{ self.getLine(), self.vmSnapShot.ip - 1, self.message });
        }

        fn getLine(self: *const Diagnostic) usize {
            return self.vmSnapShot.chunk.lineSlice[self.vmSnapShot.ip - 1];
        }
    };

    const OperandType = enum {
        number,
        string,
        boolean,

        fn GetType(comptime self: OperandType) type {
            return switch (self) {
                .number => f64,
                .string => []const u8,
                .boolean => bool,
            };
        }
    };

    pub fn initSettings(debugFlag: bool, alloc: Allocator) Allocator.Error!VM {
        return .{
            .debugFlag = debugFlag,
            .stack = try vmStack.Stack.init(alloc),
            .stringPool = try table.Table.init(alloc),
            .globals = try table.Table.init(alloc),
        };
    }

    pub fn deinit(self: *VM, alloc: Allocator) void {
        self.gcAlloc.freeAll(alloc);
        self.gcAlloc.deinit(alloc);
        self.stack.deinit(alloc);
        self.stringPool.deinit(alloc);
        self.globals.deinit(alloc);
    }

    pub fn setChunk(self: *VM, chunk: *const bcInfo.Chunk) void {
        self.chunk = chunk;
        // For the repl session, ip and stack needs to be reset
        self.ip = 0;
        self.stack.clear();
    }

    pub fn execute(self: *VM, writer: *std.Io.Writer, alloc: Allocator, diagnostics: *Diagnostic) !void {
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
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | constant: ", .{self.ip - 1});
                    }
                    const valueAddr = self.advance();
                    const value = self.chunk.constantSlice[valueAddr];
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
                        diagnostics.setContext(self, "negate operation can only have number operands");
                        return Error.RuntimeError;
                    } else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    }
                },
                .AddOp, .SubOp, .MultOp, .DivOp => {
                    try self.doBinaryOp(opCode, writer, alloc, diagnostics);
                },
                .PrintOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | print: ", .{self.ip - 1});
                    }
                    const value = if (self.stack.pop()) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    try writer.print("{f}\n", .{value});
                },
                .NilOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | nilOp \n", .{self.ip - 1});
                    }
                    try self.stack.push(values.Value{ .nil = 1 });
                },
                .DefineGlobalOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | defGlobal: ", .{self.ip - 1});
                    }
                    const value = if (self.stack.pop()) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    const targetConstant = self.chunk.constantSlice[self.advance()];
                    const defineTarget: *strings.ObjectString = if (targetConstant.isObj()) @ptrCast(@alignCast(targetConstant.asObj())) else {
                        diagnostics.setContext(self, "Unassignable target");
                        return Error.CompileError;
                    };
                    _ = try self.globals.set(defineTarget, value, alloc);
                    if (self.debugFlag) {
                        try writer.print("{s}: {f}\n", .{ defineTarget.getString(), value });
                    }
                    _ = self.stack.pop();
                },
                .GetGlobalOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | getGlobal: ", .{self.ip - 1});
                    }
                    const valueAddr = self.advance();
                    const nameVal = self.chunk.constantSlice[valueAddr];
                    const nameObjStr = nameBlock: {
                        if (!nameVal.isObj()) break :nameBlock null;
                        const valueObj = nameVal.asObj();
                        if (!valueObj.isString()) break :nameBlock null;
                        break :nameBlock @as(*strings.ObjectString, @ptrCast(@alignCast(valueObj)));
                    } orelse {
                        diagnostics.setContext(self, "Unaccessible variable <should show what was tried to be accessed>");
                        return Error.CompileError;
                    };
                    const value = self.globals.get(nameObjStr) orelse {
                        diagnostics.setContext(self, "Unknown variable used");
                        return Error.RuntimeError;
                    };
                    if (self.debugFlag) {
                        try writer.print("got {f} from {s}\n", .{ value, nameObjStr.getString() });
                    }
                    try self.stack.push(value);
                },
                .SetGlobalOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | setGlobal: ", .{self.ip - 1});
                    }
                    const valueAddr = self.advance();
                    const nameVal = self.chunk.constantSlice[valueAddr];
                    const nameObjStr = nameBlock: {
                        if (!nameVal.isObj()) break :nameBlock null;
                        const valueObj = nameVal.asObj();
                        if (!valueObj.isString()) break :nameBlock null;
                        break :nameBlock @as(*strings.ObjectString, @ptrCast(@alignCast(valueObj)));
                    } orelse {
                        diagnostics.setContext(self, "Unaccessible variable <should show what was tried to be accessed>");
                        return Error.RuntimeError;
                    };
                    const assignVal = if (self.stack.peek(0)) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    const oldVal = if (self.globals.get(nameObjStr)) |v| v else {
                        diagnostics.setContext(self, "Assignment to undeclared variable");
                        return Error.RuntimeError;
                    };
                    // Don't check if it's a re-define
                    _ = try self.globals.set(nameObjStr, assignVal, alloc);
                    if (self.debugFlag) {
                        try writer.print("{s}: {f} -> {f}\n", .{ nameObjStr.getString(), oldVal, assignVal });
                    }
                },
                .DefineLocalOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | defLocal: ", .{self.ip - 1});
                    }
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in define stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }
                    const value = self.stack.stackArray[slot];
                    if (self.debugFlag) {
                        try writer.print("{d:>3}: {f}\n", .{ slot, value });
                    }
                },
                .GetLocalOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | getLocal: ", .{self.ip - 1});
                    }
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in get stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }

                    const value = self.stack.stackArray[slot];
                    try self.stack.push(value);
                    if (self.debugFlag) {
                        try writer.print("{d:>3}: {f}\n", .{ slot, value });
                    }
                },
                .SetLocalOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | setLocal: ", .{self.ip - 1});
                    }
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in set stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }

                    const newVal = if (self.stack.peek(0)) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    if (self.debugFlag) {
                        try writer.print("slot:{d:>3} : {f} -> {f}\n", .{ slot, self.stack.stackArray[slot], newVal });
                    }
                    self.stack.stackArray[slot] = newVal;
                },
                .PopOp => {
                    if (self.debugFlag) {
                        try writer.print("{d:0>4} | popOp: ", .{self.ip - 1});
                    }
                    if (self.stack.pop()) |v| {
                        try writer.print("{f}\n", .{v});
                    } else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    }
                },
                // else => return Error.CompileErr,
            }
            try writer.flush(); // Needed here to check where the runtimeError actually happened(during execution trace)
        }
        if (self.debugFlag) {
            try writer.print("==== VM Execute Trace ====\n", .{});
        }
    }

    fn doBinaryOp(self: *VM, opCode: bc.opCode, writer: *std.Io.Writer, alloc: Allocator, diagnostics: *Diagnostic) !void {
        const operatorName = switch (opCode) {
            .AddOp => "+",
            .SubOp => "-",
            .MultOp => "*",
            .DivOp => "/",
            else => unreachable,
        };
        if (self.debugFlag) {
            try writer.print("{d:0>4} | {s}: ", .{ self.ip - 1, operatorName });
        }

        const operandsNum = try self.unboxOperands(OperandType.number);
        if (operandsNum) |o| {
            _ = self.stack.pop();
            _ = self.stack.pop();
            const result = switch (opCode) {
                .AddOp => o.lVal + o.rVal,
                .SubOp => o.lVal - o.rVal,
                .MultOp => o.lVal * o.rVal,
                .DivOp => o.lVal / o.rVal,
                else => unreachable,
            };
            if (self.debugFlag) {
                try writer.print("{d}\n", .{result});
            }
            try self.stack.push(values.Value{ .number = result });
            return;
        }

        const operandsStr = try self.unboxOperands(OperandType.string);
        if (operandsStr != null and opCode == .AddOp) {
            const o = if (operandsStr) |v| v else unreachable;
            _ = self.stack.pop();
            _ = self.stack.pop();
            if (opCode != .AddOp) return Error.RuntimeError;

            const concatString = try std.mem.concat(alloc, u8, &.{ o.lVal, o.rVal });
            defer alloc.free(concatString);
            const ptr = try strings.makeString(concatString, concatString.len, &self.gcAlloc, &self.stringPool, alloc);
            if (self.debugFlag) {
                try writer.print("{s}\n", .{ptr.getString()});
            }
            try self.stack.push(values.Value{ .obj = @ptrCast(ptr) });
            return;
        }

        const errMsg = switch (opCode) {
            .AddOp => "Operands of operator '+' must both have type number or string",
            .SubOp => "Operands of operator '-' must both have type number",
            .MultOp => "Operands of operator '*' must both have type number",
            .DivOp => "Operands of operator '/' must both have type number",
            else => unreachable,
        };
        diagnostics.setContext(self, errMsg);
        return Error.RuntimeError;
    }

    fn unboxOperands(self: *VM, comptime expectedType: OperandType) Error!?struct { lVal: expectedType.GetType(), rVal: expectedType.GetType() } {
        const rPeek = self.stack.peek(0) orelse return Error.CompileError;
        const lPeek = self.stack.peek(1) orelse return Error.CompileError;

        switch (expectedType) {
            .number => {
                const isNumLeft = lPeek.isNum();
                const isNumRight = rPeek.isNum();

                if (isNumLeft and isNumRight) {
                    const lVal = lPeek.asNum();
                    const rVal = rPeek.asNum();
                    return .{ .lVal = lVal, .rVal = rVal };
                }
            },
            .string => {
                const isStrLeft = result: {
                    const lObj = if (lPeek.isObj()) lPeek.asObj() else break :result false;
                    break :result lObj.kind == objects.ObjectType.String;
                };
                const isStrRight = result: {
                    const rObj = if (rPeek.isObj()) rPeek.asObj() else break :result false;
                    break :result rObj.kind == objects.ObjectType.String;
                };

                if (isStrLeft and isStrRight) {
                    const lVal = lPeek.asObj().getString();
                    const rVal = rPeek.asObj().getString();

                    return .{ .lVal = lVal, .rVal = rVal };
                }
            },
            .boolean => {
                const isBoolLeft = lPeek.isBool();
                const isBoolRight = rPeek.isBool();

                if (isBoolLeft and isBoolRight) {
                    const lVal = lPeek.asBool();
                    const rVal = rPeek.asBool();
                    return .{ .lVal = lVal, .rVal = rVal };
                }
            },
        }
        return null;
    }

    fn isAtEnd(
        self: *const VM,
    ) bool {
        return (self.ip >= self.chunk.codeSlice.len);
    }

    fn advance(self: *VM) u8 {
        self.ip += 1;
        return self.chunk.codeSlice[self.ip - 1];
    }
};
