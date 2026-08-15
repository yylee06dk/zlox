const std = @import("std");
const print = std.debug.print;
const tokens = @import("tokens.zig");
const ascii = std.ascii;
const TokenList = std.ArrayList(tokens.Token);
const Allocator = std.mem.Allocator;

const ScanError = error{
    UnknownCharacter,
    UnterminatedString,
};

pub const Diagnostic = struct {
    // byte info
    start: usize = 0,
    length: usize = 0,
    // error info
    errorType: ScanError = undefined,
    // position info
    line: usize = 1,
    column: usize = 1,

    fn setContext(self: *Diagnostic, scanner: *Scanner, err: ScanError, length: usize) void {
        self.start = scanner.current - length;
        self.length = length;
        self.errorType = err;
        self.line = scanner.line;
        self.column = scanner.column - length;
    }

    pub fn getLexeme(self: *const Diagnostic, source: []const u8) []const u8 {
        return source[self.start .. self.start + self.length];
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

    pub fn scanTokens(self: *Scanner, alloc: Allocator, diagnostics: *std.ArrayList(Diagnostic)) ![]tokens.Token {
        var tokenList: TokenList = .empty;
        errdefer tokenList.deinit(alloc);

        var diagnostic: Diagnostic = Diagnostic{};

        self.skipWhiteSpace();
        while (!self.isAtEnd()) {
            const token = self.scanToken(&diagnostic) catch {
                try diagnostics.append(alloc, diagnostic);
                continue; // Error recorded, on to the next one!
            } orelse continue; // Skipping this one

            try tokenList.append(alloc, token);
        }

        const EOFtoken = self.makeToken(0, tokens.TokenType.EOF);
        try tokenList.append(alloc, EOFtoken);

        return try tokenList.toOwnedSlice(alloc);
    }

    fn scanToken(self: *Scanner, context: *Diagnostic) ScanError!?tokens.Token {
        defer self.skipWhiteSpace();
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
                    const res, const len = self.string();
                    const token = res catch |err| {
                        context.setContext(self, err, len);
                        return err;
                    };
                    return token;
                }
                if (ascii.isAlphabetic(c)) {
                    return self.identifier();
                }
                context.setContext(self, ScanError.UnknownCharacter, 1);
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

    fn string(self: *Scanner) struct { ScanError!tokens.Token, usize } {
        const start = self.current; // Ignore the starting '"'
        while (self.peek()) |c| {
            if (c == '"') {
                const token = self.makeToken(self.current - start, tokens.TokenType.String);
                _ = self.advance(); // Consume the closing quote.
                return .{ token, self.current - start };
            }

            _ = self.advance();
        }

        return .{ ScanError.UnterminatedString, self.current - start };
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
            self.column = 1;
        } else {
            self.column += 1;
        }
        self.current += 1;
        return cur;
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.source.len <= self.current;
    }

    // -------------------- Pretty Printing

    pub fn printErrors(diagnosticList: *const std.ArrayList(Diagnostic), source: []const u8) void {
        print("==== Scanning Errors ====\n", .{});
        for (diagnosticList.items, 0..) |diagnostic, idx| {
            print("{d:>3}: At line {d:>3}, column: {d:>3} | {} happened at {s}\n", .{ idx + 1, diagnostic.line, diagnostic.column, diagnostic.errorType, diagnostic.getLexeme(source) });
        }
    }

    pub fn printResults(tokenList: []tokens.Token, source: []const u8, writer: *std.Io.Writer) !void {
        print("==== Scan Results ====\n", .{});
        for (tokenList, 0..) |token, idx| {
            try writer.print("{d:>3}: {s:>12} at line {d:>3}, column: {d:>3} | {s}\n", .{ idx + 1, token.kind.toString(), token.line, token.column, token.getLexeme(source) });
        }
    }
};
