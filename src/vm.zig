const std = @import("std");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const vmStack = @import("vmStack.zig");
const values = @import("values.zig");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const strings = @import("strings.zig");
const functions = @import("functions.zig");
const table = @import("table.zig");

const print = std.debug.print;
const t = std.debug.print;
const Allocator = std.mem.Allocator;
const maxFrameCount = 64;

pub const VM = struct {
    frames: []CallFrame,
    frameCount: usize,
    debugFlag: bool = false,
    stack: vmStack.Stack,
    stringPool: table.Table,
    globals: table.Table,
    gcAlloc: memory.GCAllocator = .{},

    fn getCurrentFrame(self: *const VM) *CallFrame {
        return &self.frames[self.frameCount - 1];
    }

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
            print("zlox: RuntimeError: [line:{d:>3}|ip:{d:0>4}] {s}\n", .{ self.getLine(), self.vmSnapShot.getCurrentFrame().ip - 1, self.message });
        }

        fn getLine(self: *const Diagnostic) usize {
            const ip = self.vmSnapShot.getCurrentFrame().ip;
            return self.vmSnapShot.getCurrentFrame().function.chunk.lineSlice[ip];
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

    const CallFrame = struct {
        function: *const functions.ObjectFunction,
        ip: usize,
        basePtr: usize,
    };

    pub fn initSettings(debugFlag: bool, alloc: Allocator) Allocator.Error!VM {
        return .{
            .frames = try alloc.alloc(CallFrame, maxFrameCount),
            .frameCount = 0,
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

    pub fn setTargetFunction(self: *VM, targetFunc: *functions.ObjectFunction) !void {
        // For the repl session, stack needs to be reset
        self.stack.clear();

        const basePtr = self.stack.length;
        try self.stack.push(.{ .obj = .{ .Function = targetFunc } }); // like calling the script/main function
        // No parameters! no need to do additional pushing stuffs

        self.frames[self.frameCount] = .{ .function = targetFunc, .ip = 0, .basePtr = basePtr };
        self.frameCount += 1;
    }

    pub fn execute(self: *VM, writer: *std.Io.Writer, alloc: Allocator, diagnostics: *Diagnostic) !void {
        if (self.debugFlag) {
            try writer.print("==== VM Execute Trace: {s} ====\n", .{self.getCurrentFrame().function.getName()});
        }
        while (!self.isAtEnd()) {
            const curCode = self.advance();
            const opCode: bc.opCode = @enumFromInt(curCode);
            switch (opCode) {
                .ReturnOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | returned, peek: {?}\n", .{ self.getCurrentFrame().ip - 1, self.stack.peek(0) });
                    }
                },
                .ConstantOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | constant: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const valueAddr = self.advance();
                    const value = self.getCurrentFrame().function.chunk.constantSlice[valueAddr];
                    try self.stack.push(value);
                    if (self.debugFlag) {
                        try writer.print("{}\n", .{value});
                    }
                },
                .NegateOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | negate: ", .{self.getCurrentFrame().ip - 1});
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
                        try writer.print("+{d:0>4} | print: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const value = if (self.stack.pop()) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    try writer.print("{f}\n", .{value});
                },
                .NilOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | nilOp \n", .{self.getCurrentFrame().ip - 1});
                    }
                    try self.stack.push(values.Value{ .nil = 1 });
                },
                .DefineGlobalOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | defGlobal: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const value = if (self.stack.pop()) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    const targetConstant = self.getCurrentFrame().function.chunk.constantSlice[self.advance()];
                    const targetConstantObj = if (targetConstant.isObj()) targetConstant.asObj() else {
                        diagnostics.setContext(self, "Unassignable target");
                        return Error.CompileError;
                    };
                    const defineTarget: *strings.ObjectString = if (std.meta.activeTag(targetConstantObj) == .String) targetConstantObj.String else {
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
                        try writer.print("+{d:0>4} | getGlobal: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const valueAddr = self.advance();
                    const nameVal = self.getCurrentFrame().function.chunk.constantSlice[valueAddr];
                    const nameObjStr = nameBlock: {
                        if (!nameVal.isObj()) break :nameBlock null;
                        const valueObj = nameVal.asObj();
                        if (!valueObj.isString()) break :nameBlock null;
                        break :nameBlock valueObj.String;
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
                        try writer.print("+{d:0>4} | setGlobal: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const valueAddr = self.advance();
                    const nameVal = self.getCurrentFrame().function.chunk.constantSlice[valueAddr];
                    const nameObjStr = nameBlock: {
                        if (!nameVal.isObj()) break :nameBlock null;
                        const valueObj = nameVal.asObj();
                        if (!valueObj.isString()) break :nameBlock null;
                        break :nameBlock valueObj.String;
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
                        try writer.print("+{d:0>4} | defLocal: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in define stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }
                    const trueAddr = self.getCurrentFrame().basePtr + self.getCurrentFrame().function.arity + slot;
                    const value = self.stack.stackArray[trueAddr];
                    if (self.debugFlag) {
                        try writer.print("{d:>3}: {f}\n", .{ slot, value });
                    }
                },
                .GetLocalOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | getLocal: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in get stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }

                    const trueAddr = self.getCurrentFrame().basePtr + self.getCurrentFrame().function.arity + slot;
                    const value = self.stack.stackArray[trueAddr];
                    try self.stack.push(value);
                    if (self.debugFlag) {
                        try writer.print("{d:>3}: {f}\n", .{ slot, value });
                    }
                },
                .SetLocalOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | setLocal: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in set stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }

                    const trueAddr = self.getCurrentFrame().basePtr + self.getCurrentFrame().function.arity + slot;
                    const newVal = if (self.stack.peek(0)) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    if (self.debugFlag) {
                        try writer.print("slot:{d:>3} : {f} -> {f}\n", .{ slot, self.stack.stackArray[slot], newVal });
                    }
                    self.stack.stackArray[trueAddr] = newVal;
                },

                .JumpIfFalseOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | jumpIfFalse: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const short = self.advanceShort();
                    const condition = if (self.stack.peek(0)) |v| v else {
                        diagnostics.setContext(self, "Expected value in stack");
                        return Error.CompileError;
                    };
                    const conditionBool = if (condition.isBool()) condition.asBool() else {
                        diagnostics.setContext(self, "Expected boolean value in stack");
                        return Error.RuntimeError;
                    };
                    if (!conditionBool) {
                        self.getCurrentFrame().ip += short;
                    }
                    const trueJump = if (!conditionBool) short else 0;
                    if (self.debugFlag) {
                        try writer.print("condition: {}, jumped {d:>4}\n", .{ conditionBool, trueJump });
                    }
                },
                .JumpOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | jump: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const short = self.advanceShort();
                    self.getCurrentFrame().ip += short;
                    if (self.debugFlag) {
                        try writer.print("jumped {d:>4}\n", .{short});
                    }
                },
                .LoopOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | loop: ", .{self.getCurrentFrame().ip - 1});
                    }
                    const short = self.advanceShort();
                    self.getCurrentFrame().ip -= short;
                    if (self.debugFlag) {
                        try writer.print("jumped -{d:>4}\n", .{short});
                    }
                },
                .PopOp => {
                    if (self.debugFlag) {
                        try writer.print("+{d:0>4} | popOp: ", .{self.getCurrentFrame().ip - 1});
                    }
                    if (self.stack.pop()) |v| {
                        if (self.debugFlag) try writer.print("{f}\n", .{v});
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
        std.debug.assert(self.frameCount != 0);
        self.frameCount -= 1;
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
            try writer.print("+{d:0>4} | {s}: ", .{ self.getCurrentFrame().ip - 1, operatorName });
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
            const strPtr = try strings.makeString(concatString, concatString.len, &self.gcAlloc, &self.stringPool, alloc);
            if (self.debugFlag) {
                try writer.print("{s}\n", .{strPtr.getString()});
            }
            try self.stack.push(values.Value{ .obj = .{ .String = strPtr } });
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
                    break :result std.meta.activeTag(lObj) == .String;
                };
                const isStrRight = result: {
                    const rObj = if (rPeek.isObj()) rPeek.asObj() else break :result false;
                    break :result std.meta.activeTag(rObj) == .String;
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
        return (self.getCurrentFrame().ip >= self.getCurrentFrame().function.chunk.codeSlice.len);
    }

    fn advance(self: *VM) u8 {
        self.getCurrentFrame().ip += 1;
        return self.getCurrentFrame().function.chunk.codeSlice[self.getCurrentFrame().ip - 1];
    }
    fn advanceShort(self: *VM) u16 {
        self.getCurrentFrame().ip += 2;
        const upperU8 = @as(u16, self.getCurrentFrame().function.chunk.codeSlice[self.getCurrentFrame().ip - 2]);
        const lowerU8 = @as(u16, self.getCurrentFrame().function.chunk.codeSlice[self.getCurrentFrame().ip - 1]);
        const offset: u16 = upperU8 << 8 | lowerU8;
        return offset;
    }
};
