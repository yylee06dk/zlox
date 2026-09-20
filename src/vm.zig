const std = @import("std");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const vmStack = @import("vmStack.zig");
const values = @import("values.zig");
const memory = @import("memory.zig");
const objects = @import("objects.zig");
const objectStore = @import("objectStore.zig");
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

    fn getConst(self: *const VM, addr: usize) values.Value {
        return self.getCurrentFrame().function.chunk.constantSlice[addr];
    }

    fn getCode(self: *const VM, addr: usize) u8 {
        return self.getCurrentFrame().function.chunk.codeSlice[addr];
    }

    fn getLine(self: *const VM, addr: usize) usize {
        return self.getCurrentFrame().function.chunk.lineSlice[addr];
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
            print("\nzlox: RuntimeError: [line:{d:>3}|ip:{d:0>4}] {s}\n", .{ self.getLine(), self.vmSnapShot.getCurrentFrame().ip - 1, self.message });
            var current = self.vmSnapShot.frameCount - 1;
            while (current > 0) : (current -= 1) {
                const currentFrame = self.vmSnapShot.frames[current];
                const currentLine = currentFrame.function.chunk.lineSlice[0]; // Correct? can't it be empty?
                print("[line:{d:>3}] in call to {f}\n", .{ currentLine, currentFrame.function });
            }
        }

        pub fn reportFatal(self: *Diagnostic) void {
            print("\nzlox: FATALERROR: [line:{d:>3}|ip:{d:0>4}] {s}\n", .{ self.getLine(), self.vmSnapShot.getCurrentFrame().ip - 1, self.message });
            var current = self.vmSnapShot.frameCount - 1;
            while (current > 0) : (current -= 1) {
                const currentFrame = self.vmSnapShot.frames[current];
                const currentLine = currentFrame.function.chunk.lineSlice[0]; // Correct? can't it be empty?
                print("[line:{d:>3}] in call to {f}\n", .{ currentLine, currentFrame.function });
            }
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
        function: *const objects.Object.Function,
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
        alloc.free(self.frames);
    }

    pub fn setTargetFunction(self: *VM, targetFunc: *objects.Object.Function) !void {
        // For the repl session, stack needs to be reset
        self.stack.clear();

        const basePtr = self.stack.length;
        try self.stack.push(.{ .function = targetFunc }); // like calling the script/main function
        // No parameters! no need to do additional pushing stuffs

        self.frames[self.frameCount] = .{ .function = targetFunc, .ip = 0, .basePtr = basePtr };
        self.frameCount += 1;
    }

    pub fn execute(self: *VM, writer: *std.Io.Writer, alloc: Allocator, diagnostics: *Diagnostic) !void {
        if (self.debugFlag) {
            try writer.print("==== VM Execute Trace ====\n", .{});
        }
        while (self.frameCount >= 1 and !self.isAtEnd()) {
            const curCode = self.advance();
            const opCode: bc.opCode = @enumFromInt(curCode);
            if (self.debugFlag) {
                try writer.print("{f}+{d:0>4} | {s}: ", .{ self.getCurrentFrame().function.*, self.getCurrentFrame().ip - 1, opCode.toString() });
            }
            switch (opCode) {
                .ReturnOp => {
                    const retVal = try self.safePop(diagnostics);
                    if (self.debugFlag) {
                        try writer.print("{f}", .{retVal});
                    }
                    try self.cleanCurrentCall(retVal, diagnostics);
                },
                .ConstantOp => {
                    const valueAddr = self.advance();
                    const value = self.getConst(valueAddr);
                    try self.safePush(value, diagnostics);
                    if (self.debugFlag) {
                        try writer.print("{f}", .{value});
                    }
                },
                .NegateOp => {
                    const value = try self.safePop(diagnostics);
                    if (value.isNum()) {
                        if (self.debugFlag) {
                            try writer.print("{d} -> {d}", .{ value.asNum(), -value.asNum() });
                        }
                        try self.safePush(values.Value{ .number = -value.asNum() }, diagnostics);
                        continue;
                    }
                    diagnostics.setContext(self, "negate operation can only have number operands");
                    return Error.RuntimeError;
                },
                .AddOp, .SubOp, .MultOp, .DivOp => {
                    try self.doBinaryOp(opCode, writer, alloc, diagnostics);
                },
                .EqOp, .NeqOp => {
                    try self.doEqualOp(opCode, writer, diagnostics);
                },
                .LessOp, .GreatOp, .LeqOp, .GeqOp => {
                    try self.doCompareOp(opCode, writer, diagnostics);
                },
                .PrintOp => {
                    const value = try self.safePop(diagnostics);
                    try writer.print("{f}\n", .{std.fmt.alt(value, .formatDisplay)});
                },
                .NilOp => {
                    try self.safePush(values.Value{ .nil = 1 }, diagnostics);
                },
                .DefineGlobalOp => {
                    const value = try self.safePop(diagnostics);

                    const defTarget = self.getConst(self.advance()).asString() orelse {
                        diagnostics.setContext(self, "Unassignable");
                        return Error.CompileError;
                    };

                    _ = try self.globals.set(defTarget, value, alloc);
                    if (self.debugFlag) {
                        try writer.print("{s}: {f}", .{ defTarget.getString(), value });
                    }
                },
                .GetGlobalOp => {
                    const nameObjStr = self.getConst(self.advance()).asString() orelse {
                        diagnostics.setContext(self, "Unaccessible variable <should show what was tried to be accessed>");
                        return Error.CompileError;
                    };
                    const value = self.globals.get(nameObjStr) orelse {
                        diagnostics.setContext(self, "Unknown variable used");
                        return Error.RuntimeError;
                    };
                    if (self.debugFlag) {
                        try writer.print("got {f} from {s}", .{ value, nameObjStr.getString() });
                    }
                    try self.stack.push(value);
                },
                .SetGlobalOp => {
                    const nameObjStr = self.getConst(self.advance()).asString() orelse {
                        diagnostics.setContext(self, "Unaccessible variable <should show what was tried to be accessed>");
                        return Error.RuntimeError;
                    };
                    const assignVal = try self.safePeek(diagnostics, 0);
                    const oldVal = if (self.globals.get(nameObjStr)) |v| v else {
                        diagnostics.setContext(self, "Assignment to undeclared variable");
                        return Error.RuntimeError;
                    };
                    // Don't check if it's a re-define
                    _ = try self.globals.set(nameObjStr, assignVal, alloc);
                    if (self.debugFlag) {
                        try writer.print("{s}: {f} -> {f}", .{ nameObjStr.getString(), oldVal, assignVal });
                    }
                },
                // Actually not needed but for debugging purposes, it's here
                .DefineLocalOp => {
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in define stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }
                    const trueAddr = self.getCurrentFrame().basePtr + slot;
                    const value = self.stack.stackArray[trueAddr];
                    if (self.debugFlag) {
                        try writer.print("{d:>3}: {f}", .{ slot, value });
                    }
                },
                .GetLocalOp => {
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in get stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }

                    const trueAddr = self.getCurrentFrame().basePtr + slot;
                    const value = self.stack.stackArray[trueAddr];
                    try self.safePush(value, diagnostics);
                    if (self.debugFlag) {
                        try writer.print("{d:>3}: {f}", .{ slot, value });
                    }
                },
                .SetLocalOp => {
                    const slot = self.advance();
                    if (slot >= self.stack.length) {
                        diagnostics.setContext(self, "local variable not found in set stage, should be resolved in compile stage");
                        return Error.CompileError;
                    }

                    const trueAddr = self.getCurrentFrame().basePtr + self.getCurrentFrame().function.arity + slot;
                    const newVal = try self.safePeek(diagnostics, 0);
                    if (self.debugFlag) {
                        try writer.print("slot:{d:>3} : {f} -> {f}", .{ slot, self.stack.stackArray[trueAddr], newVal });
                    }
                    self.stack.stackArray[trueAddr] = newVal;
                },

                .JumpIfFalseOp => {
                    const short = self.advanceShort();
                    const condition = try self.safePeek(diagnostics, 0);
                    const conditionBool = if (condition.isBool()) condition.asBool() else {
                        diagnostics.setContext(self, "Expected boolean value in stack");
                        return Error.RuntimeError;
                    };
                    if (!conditionBool) {
                        self.getCurrentFrame().ip += short;
                    }
                    const trueJump = if (!conditionBool) short else 0;
                    if (self.debugFlag) {
                        try writer.print("condition: {}, jumped {d:>4}", .{ conditionBool, trueJump });
                    }
                },
                .JumpOp => {
                    const short = self.advanceShort();
                    self.getCurrentFrame().ip += short;
                    if (self.debugFlag) {
                        try writer.print("jumped {d:>4}", .{short});
                    }
                },
                .LoopOp => {
                    const short = self.advanceShort();
                    self.getCurrentFrame().ip -= short;
                    if (self.debugFlag) {
                        try writer.print("jumped -{d:>4}", .{short});
                    }
                },
                .CallOp => {
                    const argCount = self.advance();
                    const basePtr = self.stack.length - argCount - 1;
                    const funPtr = (try self.safePeek(diagnostics, argCount)).asFunction() orelse {
                        diagnostics.setContext(self, "Uncallable value given <show it>");
                        return Error.RuntimeError;
                    };

                    self.frames[self.frameCount] = .{ .function = funPtr, .ip = 0, .basePtr = basePtr };
                    self.frameCount += 1;

                    if (self.frameCount == maxFrameCount) {
                        diagnostics.setContext(self, "Stack Overflow");
                        return Error.RuntimeError;
                    }

                    // Exact amount of arguments given?
                    if (funPtr.arity != argCount) {
                        diagnostics.setContext(self, "Function call has different arity");
                        return Error.RuntimeError;
                    }
                    if (self.debugFlag) {
                        try writer.print("{f} in depth {d} with args", .{ funPtr, self.frameCount });
                        var idx = argCount;
                        while (idx > 0) : (idx -= 1) {
                            const arg = self.stack.stackArray[self.stack.length - idx];
                            try writer.print(" {f}", .{arg});
                        }
                    }
                },
                .PopOp => {
                    const value = try self.safePop(diagnostics);
                    if (self.debugFlag) try writer.print("{f}", .{value});
                },
                // else => return Error.CompileErr,
            }
            if (self.debugFlag and opCode != .PrintOp) {
                try writer.print("\n", .{});
            }
            try writer.flush(); // Needed here to check where the runtimeError actually happened(during execution trace)

            if (self.isAtEnd()) { // End of function call (the function call may be a call to _script_)
                try self.cleanCurrentCall(null, diagnostics);
            }
        }
        if (self.debugFlag and self.frameCount == 0) {
            try writer.print("==== VM Execute Trace ====\n\n", .{});
        }
    }

    fn doBinaryOp(self: *VM, opCode: bc.opCode, writer: *std.Io.Writer, alloc: Allocator, diagnostics: *Diagnostic) !void {
        const operator = switch (opCode) {
            .AddOp => "+",
            .SubOp => "-",
            .MultOp => "*",
            .DivOp => "/",
            else => unreachable,
        };
        const operandsNum = try self.unboxOperands(OperandType.number);
        if (operandsNum) |o| {
            _ = try self.safePop(diagnostics);
            _ = try self.safePop(diagnostics);
            const result = switch (opCode) {
                .AddOp => o.lVal + o.rVal,
                .SubOp => o.lVal - o.rVal,
                .MultOp => o.lVal * o.rVal,
                .DivOp => o.lVal / o.rVal,
                else => unreachable,
            };
            if (self.debugFlag) {
                try writer.print("{d} {s} {d} -> {}", .{ o.lVal, operator, o.rVal, result });
            }
            try self.stack.push(values.Value{ .number = result });
            return;
        }

        const operandsStr = try self.unboxOperands(OperandType.string);
        if (operandsStr != null and opCode == .AddOp) {
            const o = if (operandsStr) |v| v else unreachable;
            _ = try self.safePop(diagnostics);
            _ = try self.safePop(diagnostics);
            if (opCode != .AddOp) return Error.RuntimeError;

            const concatString = try std.mem.concat(alloc, u8, &.{ o.lVal, o.rVal });
            defer alloc.free(concatString);
            const strPtr = try objectStore.makeString(concatString, concatString.len, &self.gcAlloc, &self.stringPool, alloc);
            if (self.debugFlag) {
                try writer.print("{s} {s} {s} -> {s}", .{ o.lVal, operator, o.rVal, strPtr.getString() });
            }
            try self.stack.push(.{ .string = strPtr });
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

    fn doEqualOp(self: *VM, opCode: bc.opCode, writer: *std.Io.Writer, diagnostics: *Diagnostic) !void {
        const rVal = try self.safePop(diagnostics);
        const lVal = try self.safePop(diagnostics);

        var result: bool = undefined;
        switch (opCode) {
            .EqOp => {
                if (std.meta.activeTag(lVal) != std.meta.activeTag(rVal)) { // two values are different type
                    try self.safePush(.{ .boolean = false }, diagnostics);
                    if (self.debugFlag) {
                        try writer.print("{f} == {f} -> {}", .{ lVal, rVal, false });
                    }
                    return;
                }

                result = switch (std.meta.activeTag(lVal)) {
                    .number => lVal.number == rVal.number,
                    .boolean => lVal.boolean == rVal.boolean,
                    .nil => true,
                    .string => lVal.string == rVal.string,
                    .function => lVal.function == rVal.function,
                };
            },
            .NeqOp => {
                if (std.meta.activeTag(lVal) != std.meta.activeTag(rVal)) { // two values are different type
                    try self.safePush(.{ .boolean = true }, diagnostics);
                    if (self.debugFlag) {
                        try writer.print("{f} == {f} -> {}", .{ lVal, rVal, true });
                    }
                    return;
                }

                result = switch (std.meta.activeTag(lVal)) {
                    .number => lVal.number != rVal.number,
                    .boolean => lVal.boolean != rVal.boolean,
                    .nil => false,
                    .string => lVal.string != rVal.string,
                    .function => lVal.function != rVal.function,
                };
            },
            else => unreachable,
        }
        if (self.debugFlag) {
            try writer.print("{f} == {f} -> {}", .{ lVal, rVal, result });
        }
        try self.safePush(.{ .boolean = result }, diagnostics);
    }

    fn doCompareOp(self: *VM, opCode: bc.opCode, writer: *std.Io.Writer, diagnostics: *Diagnostic) !void {
        const operator = switch (opCode) {
            .LessOp => "<",
            .GreatOp => ">",
            .LeqOp => "<=",
            .GeqOp => ">=",
            else => unreachable,
        };
        const operandsNum = try self.unboxOperands(OperandType.number);
        if (operandsNum) |o| {
            _ = try self.safePop(diagnostics);
            _ = try self.safePop(diagnostics);
            const result = switch (opCode) {
                .LessOp => o.lVal < o.rVal,
                .GreatOp => o.lVal > o.rVal,
                .LeqOp => o.lVal <= o.rVal,
                .GeqOp => o.lVal >= o.rVal,
                else => unreachable,
            };
            if (self.debugFlag) {
                try writer.print("{d} {s} {d} -> {}", .{ o.lVal, operator, o.rVal, result });
            }
            try self.stack.push(values.Value{ .boolean = result });
            return;
        }

        const errMsg = switch (opCode) {
            .LessOp => "Operands of operator '<' must be both have type number",
            .GreatOp => "Operands of operator '>' must be both have type number",
            .LeqOp => "Operands of operator '<=' must be both have type number",
            .GeqOp => "Operands of operator '>=' must be both have type number",
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
                if (lPeek.asString()) |left| {
                    const right = rPeek.asString() orelse return null;
                    const lVal = left.getString();
                    const rVal = right.getString();

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

    fn safePush(self: *VM, item: values.Value, diagnostic: *Diagnostic) !void {
        self.stack.push(item) catch |err| {
            diagnostic.setContext(self, "Stack Overflow");
            return err;
        };
    }

    fn safePop(self: *VM, diagnostic: *Diagnostic) !values.Value {
        const value = self.stack.pop() orelse {
            diagnostic.setContext(self, "Expected value in stack");
            return Error.CompileError;
        };
        return value;
    }

    fn safePeek(self: *VM, diagnostic: *Diagnostic, depth: usize) !values.Value {
        const value = self.stack.peek(depth) orelse {
            diagnostic.setContext(self, "Expected value in stack");
            return Error.CompileError;
        };
        return value;
    }

    fn cleanCurrentCall(self: *VM, returnVal: ?values.Value, diagnostic: *Diagnostic) !void {
        std.debug.assert(self.frameCount != 0);
        self.frameCount -= 1;
        self.stack.length = self.frames[self.frameCount].basePtr;
        const retVal: values.Value = if (returnVal) |v| v else .{ .nil = 1 };
        if (self.frameCount > 0) {
            try self.safePush(retVal, diagnostic);
        }
    }
};
