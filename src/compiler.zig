const std = @import("std");
const tokens = @import("tokens.zig");
const bc = @import("bytecode.zig");
const bcInfo = @import("bytecodeInfo.zig");
const values = @import("values.zig");
const strings = @import("strings.zig");
const memory = @import("memory.zig");
const vm = @import("vm.zig");

const Allocator = std.mem.Allocator;
const RuleErrorUnion = Allocator.Error || Compiler.Error;
const ruleFunc = *const fn (*Compiler, Allocator, *Compiler.Diagnostic) RuleErrorUnion!void;

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
    targetVM: *vm.VM, // We write info needed at runtime that's resolved at compile time

    const Error = error{
        ParseFailed,
    };

    // Can be upgraded much more!
    pub const Diagnostic = struct {
        token: *tokens.Token = undefined, // This requires the tokenList have longer lifetime
        message: []const u8 = undefined,

        fn setContext(self: *Diagnostic, compiler: *Compiler, message: []const u8) void {
            self.token = compiler.previous; //Always true?
            self.message = message;
        }

        pub fn report(self: *const Diagnostic, source: []const u8) void {
            print("zlox: CompileError: [line:{d:>3}|col:{d:>3}] {s} {s}\n", .{ self.token.line, self.token.column, self.message, self.token.getLexeme(source) });
        }
    };

    pub fn init(source: []const u8, tokenList: []tokens.Token, targetVM: *vm.VM) Compiler {
        return .{
            .source = source,
            .tokenList = tokenList,
            .previous = &(tokenList[0]),
            .current = &(tokenList[0]),
            .output = bcInfo.ByteCodeInfo.init(), // 72bytes
            .targetVM = targetVM,
        };
    }

    pub fn compileOwnedChunk(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !?bcInfo.Chunk {
        // This is double checked since scanner might ignore values
        // This means the input line was not empty so we scanned it, but then it came out empty since it only had errorful contents
        if (self.current.kind == tokens.TokenType.EOF) return null;
        try self.expression(alloc, diagnostic);
        if (self.current.kind != tokens.TokenType.EOF) {
            return Error.ParseFailed;
        }
        // The ownership goes to the caller
        return try self.output.deinit(alloc);
    }

    fn expression(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) !void {
        try self.parsePrecedence(Precedence.Assignment, alloc, diagnostic);
    }

    fn parsePrecedence(self: *Compiler, prec: Precedence, alloc: Allocator, diagnostic: *Diagnostic) !void {
        self.advance();
        const prevTokenType = self.previous.kind;
        const prefix = getRule(prevTokenType).prefix orelse {
            diagnostic.setContext(self, "Expected preceding expression at");
            return Error.ParseFailed;
        };

        try prefix(self, alloc, diagnostic);

        while (!self.isAtEnd() and @intFromEnum(getRule(self.current.kind).prec) >= @intFromEnum(prec)) {
            self.advance(); // We in this loop means we gonna parse the one we checked above
            const infix = getRule(self.previous.kind).infix orelse {
                diagnostic.setContext(self, "Expected following infix operator, instead got: ");
                return Error.ParseFailed;
            }; // Really bad since we entered the while loop but don't have a matching infix operator

            try infix(self, alloc, diagnostic);
        }
    }

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

    fn consume(self: *Compiler, expect: tokens.TokenType) Error!void {
        if (self.isAtEnd() or self.current.kind != expect) {
            return Error.ParseFailed;
        }
        self.advance();
        return;
    }

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

    // ------------ Parsing functions -------------
    fn literal(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Allocator.Error!void {
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

    fn number(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Allocator.Error!void {
        _ = diagnostic;
        const lexeme = self.previous.getLexeme(self.source);
        const num = std.fmt.parseFloat(f64, lexeme) catch unreachable;
        const value = values.Value{ .number = num };
        try self.writeConstant(alloc, value);
    }

    fn string(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) Allocator.Error!void {
        _ = diagnostic;
        const objPtr = try strings.makeString(self.source[self.previous.start..], self.previous.length, &self.targetVM.gcAlloc, &self.targetVM.stringPool, alloc);
        const value = values.Value{
            .obj = @ptrCast(objPtr),
        };
        try self.writeConstant(alloc, value);
    }

    // prefix parsing function for minus
    fn unary(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) (Allocator.Error || Error)!void {
        const opTokenType = self.previous.kind;

        try self.parsePrecedence(Precedence.Unary, alloc, diagnostic);

        switch (opTokenType) {
            .Minus => try self.output.writeCode(alloc, @intFromEnum(bc.opCode.NegateOp), self.previous.line),
            else => unreachable,
        }
    }

    fn binary(self: *Compiler, alloc: Allocator, diagnostic: *Diagnostic) (Allocator.Error || Error)!void {
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
};
