const std = @import("std");
const t = std.debug.print;
const tokens = @import("tokens.zig");
const ascii = std.ascii;
const TokenList = std.ArrayList(tokens.Token);
const Allocator = std.mem.Allocator;

const ScanError = error{
    UnknownCharacter,
    UnterminatedString,
    InvalidNumber,
};

const ScanErrorContext = struct {
    // Source should be known
    source: []const u8,
    // byte info
    current: usize = 0,
    // error info
    errorType: ScanError = undefined,
    // position info
    line: usize = 1,
    column: usize = 1,

    fn setContext(self: *ScanErrorContext, scanner: *Scanner, err: ScanError) void {
        self.current = scanner.current - 1;
        self.source = scanner.source;
        self.errorType = err;
        self.line = scanner.line;
        self.column = scanner.column - 1;
    }
};

pub const Scanner = struct {
    source: []const u8,
    current: usize,
    line: usize,
    column: usize,

    pub fn init(source: []const u8) Scanner {
        return .{
            .source = source,
            .current = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn scanTokens(self: *Scanner, alloc: Allocator) ![]tokens.Token {
        var tokenList: TokenList = .empty;
        errdefer tokenList.deinit(alloc);
        var scanContext: ScanErrorContext = .{
            .source = self.source,
        };

        while (!self.isAtEnd()) {
            const token = self.scanToken(&scanContext) catch |err| switch (err) {
                ScanError.UnknownCharacter => null,
                else => null,
            } orelse continue; // Skipping this one

            try tokenList.append(alloc, token);
        }

        const EOFtoken = self.makeToken(0, tokens.TokenType.EOF);
        try tokenList.append(alloc, EOFtoken);

        return try tokenList.toOwnedSlice(alloc);
    }

    fn scanToken(self: *Scanner, context: *ScanErrorContext) ScanError!?tokens.Token {
        self.skipWhiteSpace();
        const c = checkEnd: {
            if (!self.isAtEnd()) {
                break :checkEnd self.advance();
            } else {
                return null;
            }
        };
        switch (c) {
            '+' => return self.makeToken(1, tokens.TokenType.Plus),
            '-' => return self.makeToken(1, tokens.TokenType.Minus),
            '*' => return self.makeToken(1, tokens.TokenType.Star),
            '/' => return self.makeToken(1, tokens.TokenType.Slash),
            '(' => return self.makeToken(1, tokens.TokenType.LeftParen),
            ')' => return self.makeToken(1, tokens.TokenType.RightParen),
            else => {
                if (ascii.isDigit(c)) {
                    return self.number();
                }
                if (c == '"') {
                    const res = self.string() catch |err| {
                        context.setContext(self, err);
                        return err;
                    };
                    return res;
                }
                if (ascii.isAlphabetic(c)) {
                    return self.identifier();
                }
                context.setContext(self, ScanError.UnknownCharacter);
                return ScanError.UnknownCharacter;
            },
        }
    }

    fn number(self: *Scanner) tokens.Token {
        const start = self.current - 1;
        while (self.peek()) |c| {
            if (!ascii.isDigit(c)) break;
            _ = self.advance();
        }

        if (self.checkPeek('.')) {
            var temp = self.peekNext() orelse 0;

            if (ascii.isDigit(temp)) {
                _ = self.advance();

                temp = self.peek() orelse 0;
                while (ascii.isDigit(temp)) : (temp = self.peek() orelse 0) {
                    _ = self.advance();
                }
            }
        }

        const end = self.current;

        return self.makeToken(end - start, tokens.TokenType.Number);
    }

    fn string(self: *Scanner) ScanError!tokens.Token {
        const start = self.current; // Ignore the starting '"'
        while (self.peek()) |c| {
            if (c == '"') {
                const token = self.makeToken(self.current - start, tokens.TokenType.String);
                _ = self.advance(); // Consume the closing quote.
                return token;
            }

            _ = self.advance();
        }

        return ScanError.UnterminatedString;
    }

    fn identifier(self: *Scanner) tokens.Token {
        const start = self.current - 1;

        while (self.peek()) |c| {
            if (ascii.isAlphanumeric(c)) {
                _ = self.advance();
                continue;
            }
            break;
        }
        const end = self.current;
        return self.makeToken(end - start, tokens.TokenType.Identifier);
    }

    fn makeToken(self: *Scanner, length: usize, kind: tokens.TokenType) tokens.Token {
        const checkString: usize = if (kind == .String) 1 else 0;
        return .{
            .kind = kind,
            .start = self.getStart(length),
            .length = length,
            .line = self.line,
            .column = self.column - length - checkString,
        };
    }

    fn skipWhiteSpace(self: *Scanner) void {
        var cur = self.peek() orelse 0;
        while (cur == ' ' or cur == '\n' or cur == '\t') : (cur = self.peek() orelse 0) {
            _ = self.advance();
        }
    }

    fn checkPeek(self: *const Scanner, expect: u8) bool {
        if (self.peek()) |c| {
            return c == expect;
        }
        return false;
    }

    fn peek(self: *const Scanner) ?u8 {
        if (self.isAtEnd()) return null;
        return self.source[self.current];
    }

    fn peekNext(self: *const Scanner) ?u8 {
        if (self.source.len <= self.current + 1) return null;
        return self.source[self.current + 1];
    }

    fn getStart(self: *const Scanner, length: usize) usize {
        return self.current - length;
    }

    fn advance(self: *Scanner) u8 {
        const cur = self.source[self.current];
        if (cur == '\n') {
            self.line += 1;
            self.column = 0;
        } else {
            self.column += 1;
        }
        self.current += 1;
        return cur;
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.source.len <= self.current;
    }
};
