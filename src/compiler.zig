const std = @import("std");
const tokens = @import("tokens.zig");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const values = @import("values.zig");
const objects = @import("objects.zig");
const objectStore = @import("objectStore.zig");
const memory = @import("memory.zig");
const vm = @import("vm.zig");

const Allocator = std.mem.Allocator;
const Errors = Allocator.Error || Compiler.Error;
const ruleFunc = *const fn (*Compiler, Allocator, *Compiler.Diagnostic, bool) Errors!void;

const print = std.debug.print;

pub const Precedence = enum {
    None,
    Assignment,
    Or,
    And,
    Equality,
    Comparison,
    ExpressionIf,
    Term,
    Factor,
    Unary,
    Call,
    Primary,
};

pub const Rule = struct {
    prefix: ?ruleFunc = null,
    infix: ?ruleFunc = null,
    prec: Precedence = .None,
};

const ruleTable: std.enums.EnumArray(tokens.TokenType, Rule) = .initDefault(.{}, .{
    .True = .{ .prefix = Compiler.literal },
    .False = .{ .prefix = Compiler.literal },
    .Nil = .{ .prefix = Compiler.literal },
    .Number = .{ .prefix = Compiler.number },
    .String = .{ .prefix = Compiler.string },
    .Plus = .{ .infix = Compiler.binary, .prec = .Term },
    .Minus = .{ .prefix = Compiler.unary, .infix = Compiler.binary, .prec = .Term },
    .Star = .{ .infix = Compiler.binary, .prec = .Factor },
    .Slash = .{ .infix = Compiler.binary, .prec = .Factor },
    .Identifier = .{
        .prefix = Compiler.variable,
    },
    .LeftParen = .{
        .prefix = Compiler.grouping,
    },
});

fn getRule(tokenType: tokens.TokenType) Rule {
    return ruleTable.get(tokenType);
}

pub const Compiler = struct {
    source: []const u8, // Needed to get lexeme of tokens
    tokenList: []tokens.Token, // read-only, borrowed
    previous: *tokens.Token, // Direct dereference
    current: *tokens.Token,
    output: bcInfo.ByteCodeInfo, // Just an intermediate data structure used
    resolver: Resolver,
    targetVM: *vm.VM, // We write info needed at runtime that's resolved at compile time
    compileType: CompileType,
    arity: u8,
    name: ?*const objects.Object.String, //borrowed

    const Error = error{
        ParseFailed,
    };

    pub const CompileType = enum {
        Script,
        Function,
    };

    // Can be upgraded much more!
    pub const Diagnostic = struct {
        token: *tokens.Token = undefined, // This requires the tokenList have longer lifetime
        message: []const u8 = undefined,

        fn setContext(self: *Diagnostic, ownerToken: *tokens.Token, message: []const u8) void {
            self.token = ownerToken; //Always true?
            self.message = message;
        }

        pub fn report(self: *const Diagnostic, source: []const u8) void {
            print("zlox: CompileError: [line:{d:>3}|col:{d:>3}] {s} {s}\n", .{ self.token.line, self.token.column, self.message, self.token.getLexeme(source) });
        }
    };

    pub fn init(source: []const u8, tokenList: []tokens.Token, targetVM: *vm.VM, compileType: CompileType, arity: u8, name: ?*const objects.Object.String, alloc: Allocator) !Compiler {
        var temp: Compiler = .{
            .source = source,
            .tokenList = tokenList,
            .previous = &(tokenList[0]),
            .current = &(tokenList[0]),
            .output = bcInfo.ByteCodeInfo.init(), // 72bytes
            .resolver = try Resolver.init(alloc),
            .targetVM = targetVM,
            .compileType = compileType,
            .arity = arity,
            .name = name,
        };
        // Reserve first slot of (call frame's) stack with function/method name
        const funcName = if (name) |n| n else try objectStore.makeString("", 0, &targetVM.gcAlloc, &targetVM.stringPool, alloc);
        temp.resolver.locals[0] = .{ .depth = 0, .name = funcName };
        temp.resolver.localCount += 1;
        return temp;
    }

    pub fn deinit(self: *Compiler, alloc: Allocator) void {
        self.resolver.deinit(alloc);
    }

    pub fn compileOwnedFunctionObj(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !?*objects.Object.Function {
        // errdefer self.output.deinit(alloc);
        // This is double checked since scanner might ignore values
        // This means the input line was not empty so we scanned it, but then it came out empty since it only had errorful contents
        if (self.current.kind == tokens.TokenType.EOF) return null;
        while (!self.isAtEnd()) {
            try self.declaration(alloc, diagnostic);
        }
        if (self.current.kind != tokens.TokenType.EOF) {
            return Error.ParseFailed;
        }
        // The ownership goes to the caller
        const funcPtr = try objectStore.createEmptyFunction(alloc, &self.targetVM.gcAlloc);
        const chunk = try self.output.toOwnedChunk(alloc);
        try objectStore.initFunctionInplace(funcPtr, alloc, &self.targetVM.gcAlloc, self.name, chunk, self.arity);
        return funcPtr;
    }

    const Resolver = struct {
        scopeDepth: usize,
        localCount: usize,
        locals: []Local, // of length 256 (MAX_U8)

        const Local = struct {
            name: *const objects.Object.String,
            depth: usize,
        };

        pub fn init(alloc: Allocator) !Resolver {
            return .{
                .scopeDepth = 0,
                .localCount = 0,
                .locals = try alloc.alloc(Local, @as(usize, std.math.maxInt(u8)) + 1),
            };
        }

        pub fn deinit(self: *Resolver, alloc: Allocator) void {
            alloc.free(self.locals);
        }
    };

    // Resolver related functions
    fn beginScope(self: *Compiler) void {
        self.resolver.scopeDepth += 1;
    }

    fn endScope(self: *Compiler, alloc: Allocator) !void {
        if (self.resolver.scopeDepth == 0) unreachable;

        // Cleanup the scope
        var idx = self.resolver.localCount;
        while (idx > 0) {
            idx -= 1;
            const local = self.resolver.locals[idx];
            if (local.depth < self.resolver.scopeDepth) {
                break;
            }

            self.resolver.localCount -= 1;
            try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
        }
        self.resolver.scopeDepth -= 1;
    }

    pub fn declareVariable(self: *Compiler, name: *objects.Object.String, diagnostic: *Diagnostic) !void {
        if (self.resolver.localCount == std.math.maxInt(u8) + 1) {
            diagnostic.setContext(self.previous, "Too many local variables declared(max of 256) at");
            return Error.ParseFailed;
        }

        var idx = self.resolver.localCount;
        while (idx > 0) {
            idx -= 1;
            const local = self.resolver.locals[idx];
            if (local.depth < self.resolver.scopeDepth) break;
            if (local.name == name) {
                diagnostic.setContext(self.previous, "Redeclare of variable in same scope at");
                return Error.ParseFailed;
            }
        }

        self.resolver.locals[self.resolver.localCount] = .{
            .name = name,
            .depth = self.resolver.scopeDepth,
        };
        self.resolver.localCount += 1;
    }

    fn resolveLocal(self: *Compiler, name: *objects.Object.String) ?usize {
        var idx = self.resolver.localCount;
        // Search for the given name in locals list
        while (idx > 0) { // start from end to meet the innermost declaration(shadowing)
            idx -= 1;
            const local = self.resolver.locals[idx];
            if (local.name == name) { // pointer comparison via string interning
                return idx;
            }
        }
        return null;
    }
    // Resolver related functions

    // The basic blocks of the compiling process. It's like a abstraction layer
    fn declaration(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Errors!void {
        if (self.match(tokens.TokenType.Var)) {
            try self.varStatement(alloc, diagnostic);
        } else {
            try self.statement(alloc, diagnostic);
        }
    }

    fn statement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Errors!void {
        if (self.match(tokens.TokenType.Print)) {
            try self.printStatement(alloc, diagnostic);
        } else if (self.match(tokens.TokenType.LeftBrace)) {
            try self.blockStatement(alloc, diagnostic);
        } else if (self.match(tokens.TokenType.If)) {
            try self.ifStatement(alloc, diagnostic);
        } else if (self.match(tokens.TokenType.While)) {
            try self.whileStatement(alloc, diagnostic);
        } else if (self.match(tokens.TokenType.For)) {
            try self.forStatement(alloc, diagnostic);
        } else {
            try self.expressionStatement(alloc, diagnostic);
        }
    }

    fn expression(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !void {
        try self.parsePrecedence(Precedence.Assignment, alloc, diagnostic);
    }

    // climbs the precedence tree
    fn parsePrecedence(self: *Compiler, prec: Precedence, alloc: Allocator, diagnostic: *Diagnostic) !void {
        self.advance();
        const prevTokenType = self.previous.kind;
        const prefix = getRule(prevTokenType).prefix orelse {
            diagnostic.setContext(self.previous, "Expected preceding expression at");
            return Error.ParseFailed;
        };

        const canAssign = @intFromEnum(prec) <= @intFromEnum(Precedence.Assignment);
        try prefix(self, alloc, diagnostic, canAssign);

        while (!self.isAtEnd() and @intFromEnum(getRule(self.current.kind).prec) >= @intFromEnum(prec)) {
            self.advance(); // We in this loop means we gonna parse the one we checked above
            const infix = getRule(self.previous.kind).infix orelse {
                diagnostic.setContext(self.previous, "Expected following infix operator, instead got: ");
                return Error.ParseFailed;
            }; // Really bad since we entered the while loop but don't have a matching infix operator

            try infix(self, alloc, diagnostic, canAssign);
        }
    }
    // The basic blocks of the compiling process. It's like a uniform layer for compiling

    // ------------ Statement Parsing functions -------------
    fn printStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !void {
        const printToken = self.previous;
        try self.expression(alloc, diagnostic);
        try self.consume(tokens.TokenType.Semicolon, printToken, diagnostic, "Expected semicolon at");
        try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PrintOp), self.previous.line);
    }

    fn varStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !void {
        const isLocal = self.resolver.scopeDepth > 0;
        const defOp = @intFromEnum(if (isLocal) bc.opCode.DefineLocalOp else bc.opCode.DefineGlobalOp);

        try self.consume(tokens.TokenType.Identifier, self.current, diagnostic, "Expected variable name at");

        const strPtr = try objectStore.makeString(self.source[self.previous.start..], self.previous.length, &self.targetVM.gcAlloc, &self.targetVM.stringPool, alloc);
        const value: values.Value = .{ .string = strPtr };
        // Add the variable name to constant list
        const addr = try self.output.addConstant(alloc, value);
        // Add the variable itself to resolver
        if (self.resolver.scopeDepth > 0) { //local!
            try self.declareVariable(strPtr, diagnostic);
        }

        // Check if it has initializer
        if (self.match(tokens.TokenType.Equals)) {
            try self.expression(alloc, diagnostic);
        } else {
            try self.output.writeCode(alloc, @intFromEnum(bc.opCode.NilOp), self.previous.line);
        }

        try self.consume(tokens.TokenType.Semicolon, self.previous, diagnostic, "Expected semicolon at");

        if (self.resolveLocal(strPtr)) |s| {
            try self.writeBytes(alloc, defOp, @intCast(s));
        } else {
            try self.writeBytes(alloc, defOp, @intCast(addr));
        }
    }

    fn ifStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Errors!void {
        const ifToken = self.previous;
        try self.consume(tokens.TokenType.LeftParen, ifToken, diagnostic, "Expect opening parentheses after");
        const leftParenToken = self.previous;
        try self.expression(alloc, diagnostic); // Condition
        try self.consume(tokens.TokenType.RightParen, leftParenToken, diagnostic, "Expect closing parentheses for");

        const thenJmpPos = try self.markJump(alloc, @intFromEnum(bc.opCode.JumpIfFalseOp));

        // then block
        try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
        try self.statement(alloc, diagnostic);

        // Eagerly match else block
        const hasElse = self.match(tokens.TokenType.Else);
        const elseToken = self.previous;
        const elseJmpPos: ?usize = if (hasElse) try self.markJump(alloc, @intFromEnum(bc.opCode.JumpOp)) else null;

        self.patchJump(thenJmpPos, self.output.byteCodeList.items.len) catch |err| {
            diagnostic.setContext(ifToken, "Too long jump(not represantable with 16bits)");
            return err;
        };

        if (elseJmpPos) |e| {
            try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
            try self.statement(alloc, diagnostic);
            self.patchJump(e, self.output.byteCodeList.items.len) catch |err| {
                diagnostic.setContext(elseToken, "Too long jump(not represantable with 16bits)");
                return err;
            };
        }
    }

    fn whileStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Errors!void {
        const whileToken = self.previous;
        try self.consume(tokens.TokenType.LeftParen, whileToken, diagnostic, "Expect opening parentheses after");
        const leftParenToken = self.previous;
        const conditionStart = self.output.byteCodeList.items.len;
        try self.expression(alloc, diagnostic); // Condition
        try self.consume(tokens.TokenType.RightParen, leftParenToken, diagnostic, "Expect closing parentheses for");

        const jmpToEnd = try self.markJump(alloc, @intFromEnum(bc.opCode.JumpIfFalseOp));
        try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
        try self.statement(alloc, diagnostic);
        const jmpToWhile = try self.markJump(alloc, @intFromEnum(bc.opCode.LoopOp));
        try self.patchJump(jmpToWhile, conditionStart);
        try self.patchJump(jmpToEnd, self.output.byteCodeList.items.len);
        try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
    }

    fn forStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Errors!void {
        self.beginScope();
        const forToken = self.previous;
        try self.consume(tokens.TokenType.LeftParen, forToken, diagnostic, "Expect opening parentheses after");
        const leftParenToken = self.previous;

        // init
        if (self.match(tokens.TokenType.Var)) {
            try self.varStatement(alloc, diagnostic);
        } else if (self.current.kind != tokens.TokenType.Semicolon) {
            try self.expressionStatement(alloc, diagnostic);
        } else {
            try self.consume(tokens.TokenType.Semicolon, self.previous, diagnostic, "Expected semicolon after");
        } // This makes the init-section stack-effect free

        // condition
        // If no condition, this will point to the start of block! no need for something like a trueOp
        var conditionStart: ?usize = null;
        var jumpToEnd: ?usize = null;
        if (self.current.kind != tokens.TokenType.Semicolon) {
            conditionStart = self.output.byteCodeList.items.len;
            try self.expression(alloc, diagnostic);
            jumpToEnd = try self.markJump(alloc, @intFromEnum(bc.opCode.JumpIfFalseOp));
            try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
        }
        try self.consume(tokens.TokenType.Semicolon, self.previous, diagnostic, "Expected semicolon after");
        const conditionEnd = try self.markJump(alloc, @intFromEnum(bc.opCode.JumpOp));

        // updater
        const incrementStart = self.output.byteCodeList.items.len;
        if (self.current.kind != tokens.TokenType.RightParen) {
            try self.expression(alloc, diagnostic);
            try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
        }
        const incrementEnd = try self.markJump(alloc, @intFromEnum(bc.opCode.LoopOp));

        if (conditionStart) |c| {
            try self.patchJump(incrementEnd, c);
        } else {
            try self.patchJump(incrementEnd, conditionEnd - 1);
        }

        try self.consume(tokens.TokenType.RightParen, leftParenToken, diagnostic, "Expect closing parentheses for");

        try self.patchJump(conditionEnd, self.output.byteCodeList.items.len);

        try self.statement(alloc, diagnostic);

        const blockEnd = try self.markJump(alloc, @intFromEnum(bc.opCode.LoopOp));
        try self.patchJump(blockEnd, incrementStart);

        if (jumpToEnd) |j| {
            try self.patchJump(j, self.output.byteCodeList.items.len);
            try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
        }

        try self.endScope(alloc);
    }

    fn blockStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Errors!void {
        const leftBrace = self.previous;
        self.beginScope();
        while (self.current.kind != tokens.TokenType.RightBrace and !self.isAtEnd()) {
            try self.declaration(alloc, diagnostic);
        }
        try self.consume(tokens.TokenType.RightBrace, leftBrace, diagnostic, "Unclosed block at");
        try self.endScope(alloc);
    }

    fn expressionStatement(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !void {
        try self.expression(alloc, diagnostic);
        try self.consume(tokens.TokenType.Semicolon, self.previous, diagnostic, "Expected semicolon at");
        try self.output.writeCode(alloc, @intFromEnum(bc.opCode.PopOp), self.previous.line);
    }
    // ------------ Expression Parsing functions -------------
    fn literal(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) Allocator.Error!void {
        _ = canAssign;
        _ = diagnostic;
        switch (self.previous.kind) {
            .True => {
                const value = values.Value{ .boolean = true };
                try self.writeConstant(alloc, value);
            },
            .False => {
                const value = values.Value{ .boolean = false };
                try self.writeConstant(alloc, value);
            },
            .Nil => {
                const value = values.Value{ .nil = 1 };
                try self.writeConstant(alloc, value);
            },
            else => unreachable,
        }
    }

    fn grouping(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) Errors!void {
        _ = canAssign;
        const leftParen = self.previous;
        try self.expression(alloc, diagnostic);
        try self.consume(tokens.TokenType.RightParen, leftParen, diagnostic, "Unclosed parentheses at");
    }

    fn number(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) Allocator.Error!void {
        _ = canAssign;
        _ = diagnostic;
        const lexeme = self.previous.getLexeme(self.source);
        const num = std.fmt.parseFloat(f64, lexeme) catch unreachable;
        const value = values.Value{ .number = num };
        try self.writeConstant(alloc, value);
    }

    fn string(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) Allocator.Error!void {
        _ = canAssign;
        _ = diagnostic;
        const strPtr = try objectStore.makeString(self.source[self.previous.start..], self.previous.length, &self.targetVM.gcAlloc, &self.targetVM.stringPool, alloc);
        const value: values.Value = .{ .string = strPtr };
        try self.writeConstant(alloc, value);
    }

    fn variable(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) !void {
        const isLocal = self.resolver.scopeDepth > 0;

        const nameToken = self.previous;
        const strPtr = try objectStore.makeString(nameToken.getLexeme(self.source), nameToken.length, &self.targetVM.gcAlloc, &self.targetVM.stringPool, alloc);
        const value: values.Value = .{ .string = strPtr };
        const addr = try self.output.addConstant(alloc, value);
        const slot = self.resolveLocal(strPtr);
        const resolved = slot != null;
        const s = @as(u8, @intCast(if (slot) |s| s else addr));

        const setOp = @intFromEnum(if (isLocal) bc.opCode.SetLocalOp else bc.opCode.SetGlobalOp);
        const getOp = @intFromEnum(if (isLocal and resolved) bc.opCode.GetLocalOp else bc.opCode.GetGlobalOp);

        if (self.match(tokens.TokenType.Equals) and canAssign) {
            try self.expression(alloc, diagnostic);
            try self.writeBytes(alloc, setOp, s);
        } else {
            try self.writeBytes(alloc, getOp, s);
        }
    }

    // prefix parsing function for minus
    fn unary(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) Errors!void {
        _ = canAssign;
        const opTokenType = self.previous.kind;

        try self.parsePrecedence(Precedence.Unary, alloc, diagnostic);

        switch (opTokenType) {
            .Minus => try self.output.writeCode(alloc, @intFromEnum(bc.opCode.NegateOp), self.previous.line),
            else => unreachable,
        }
    }

    fn binary(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic, canAssign: bool) Errors!void {
        _ = canAssign;
        const opTokenType = self.previous.kind;
        const curPrec = getRule(opTokenType).prec;

        try self.parsePrecedence(@enumFromInt(@intFromEnum(curPrec) + 1), alloc, diagnostic);

        switch (opTokenType) {
            .Plus => try self.output.writeCode(alloc, @intFromEnum(bc.opCode.AddOp), self.previous.line),
            .Minus => try self.output.writeCode(alloc, @intFromEnum(bc.opCode.SubOp), self.previous.line),
            .Star => try self.output.writeCode(alloc, @intFromEnum(bc.opCode.MultOp), self.previous.line),
            .Slash => try self.output.writeCode(alloc, @intFromEnum(bc.opCode.DivOp), self.previous.line),
            else => unreachable,
        }
    }

    // Abstracting out basic -atom-like- steps
    fn advance(self: *Compiler) void {
        // t("1cur{}\n", .{self.current.kind});
        // t("1prev{}\n", .{self.previous.kind});
        // defer t("2cur{}\n", .{self.current.kind});
        // defer t("2prev{}\n", .{self.previous.kind});
        if (self.previous == self.current and self.current == &(self.tokenList[0])) {
            self.current = @ptrFromInt(@intFromPtr(self.current) + @sizeOf(tokens.Token));
            return;
        }
        self.previous = @ptrFromInt(@intFromPtr(self.previous) + @sizeOf(tokens.Token));
        self.current = @ptrFromInt(@intFromPtr(self.current) + @sizeOf(tokens.Token));
        return;
    }

    fn isAtEnd(self: *Compiler) bool {
        return self.current.kind == tokens.TokenType.EOF;
    }

    fn consume(self: *Compiler, expect: tokens.TokenType, owner: *tokens.Token, diagnostics: *Diagnostic, message: []const u8) !void {
        if (self.isAtEnd() or self.current.kind != expect) {
            diagnostics.setContext(owner, message);
            return Error.ParseFailed;
        }
        self.advance();
        return;
    }

    fn match(self: *Compiler, expect: tokens.TokenType) bool {
        if (self.current.kind == expect) {
            self.advance();
            return true;
        }
        return false;
    }
    // Basic functions end

    // this currently has too niche of an usage
    fn writeConstant(self: *Compiler, alloc: Allocator, value: values.Value) Allocator.Error!void {
        // Only causes Oom error
        const addr = try self.output.addConstant(alloc, value);
        if (addr > std.math.maxInt(u8)) {
            unreachable; // Temporary fix
        }

        try self.output.writeCode(
            alloc,
            @intFromEnum(bc.opCode.ConstantOp),
            self.previous.line,
        );
        try self.output.writeCode(
            alloc,
            @intCast(addr),
            self.previous.line,
        );
    }

    fn writeBytes(self: *Compiler, alloc: Allocator, fstByte: u8, scdByte: u8) !void {
        try self.output.writeCode(
            alloc,
            fstByte,
            self.previous.line,
        );
        try self.output.writeCode(
            alloc,
            scdByte,
            self.previous.line,
        );
    }

    fn markJump(self: *Compiler, alloc: Allocator, jmpType: u8) !usize {
        try self.output.writeCode(alloc, jmpType, self.previous.line);
        try self.writeBytes(alloc, 0, 0);
        const jmpValPos = self.output.byteCodeList.items.len - 2;
        return jmpValPos;
    }

    fn patchJump(self: *Compiler, patchPos: usize, targetPos: usize) !void {
        // Due to the short read during running the VM offset has a size of 2 diff for true jumping offset
        const jumpVal = if (targetPos < patchPos) patchPos - targetPos + 2 else targetPos - patchPos - 2;
        if (jumpVal > @as(usize, std.math.maxInt(u16))) {
            return Error.ParseFailed;
        }
        const upperU8: u8 = @intCast(jumpVal >> 8 & 0b11111111);
        const lowerU8: u8 = @intCast(jumpVal & 0b11111111);
        self.output.byteCodeList.items[patchPos] = upperU8;
        self.output.byteCodeList.items[patchPos + 1] = lowerU8;
    }

    // Variable parsing related functions
    fn parseVariable(self: *Compiler, alloc: Allocator, diagnostics: *Diagnostic) !usize {
        try self.consume(tokens.TokenType.Identifier, self.current, diagnostics, "Expected variable name at");
        const strPtr = try objectStore.makeString(self.source[self.previous.start..], self.previous.length, &self.targetVM.gcAlloc, &self.targetVM.stringPool, alloc);
        const value: values.Value = .{ .string = strPtr };
        return try self.output.addConstant(alloc, value);
    }

    fn namedVariable(self: *Compiler, nameToken: *tokens.Token, alloc: Allocator) !usize {
        const ptrStr = try objectStore.makeString(nameToken.getLexeme(self.source), nameToken.length, &self.targetVM.gcAlloc, &self.targetVM.stringPool, alloc);
        const value: values.Value = .{ .string = ptrStr };
        return try self.output.addConstant(alloc, value);
    }
};
