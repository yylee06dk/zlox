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

    pub fn report(self: *const Diagnostic, source: []const u8) void {
        print("zlox: scanError: [line:{d:>3}|col:{d:>3}] {s} at {s}\n", .{ self.line, self.column, @errorName(self.errorType), self.getLexeme(source) });
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
            }; // Skipping this one

            try tokenList.append(alloc, token);
        }

        const EOFtoken = self.makeToken(0, tokens.TokenType.EOF);
        try tokenList.append(alloc, EOFtoken);

        return try tokenList.toOwnedSlice(alloc);
    }

    pub fn scanToken(self: *Scanner, diagnostic: *Diagnostic) ScanError!tokens.Token {
        defer self.skipWhiteSpace();
        const c = self.advance(); // this is okay since we come here after checking isAtEnd
        switch (c) {
            '+' => return self.makeToken(1, tokens.TokenType.Plus),
            '-' => return self.makeToken(1, tokens.TokenType.Minus),
            '*' => return self.makeToken(1, tokens.TokenType.Star),
            '/' => return self.makeToken(1, tokens.TokenType.Slash),
            '(' => return self.makeToken(1, tokens.TokenType.LeftParen),
            ')' => return self.makeToken(1, tokens.TokenType.RightParen),
            '{' => return self.makeToken(1, tokens.TokenType.LeftBrace),
            '}' => return self.makeToken(1, tokens.TokenType.RightBrace),
            ';' => return self.makeToken(1, tokens.TokenType.Semicolon),
            '!' => {
                const hasEqual = self.match('=');
                return self.makeToken(if (hasEqual) 2 else 1, if (hasEqual) tokens.TokenType.BangEquals else tokens.TokenType.Bang);
            },
            '=' => {
                const hasEqual = self.match('=');
                return self.makeToken(if (hasEqual) 2 else 1, if (hasEqual) tokens.TokenType.EqualEquals else tokens.TokenType.Equals);
            },
            '>' => {
                const hasEqual = self.match('=');
                return self.makeToken(if (hasEqual) 2 else 1, if (hasEqual) tokens.TokenType.GreaterEqual else tokens.TokenType.Greater);
            },
            '<' => {
                const hasEqual = self.match('=');
                return self.makeToken(if (hasEqual) 2 else 1, if (hasEqual) tokens.TokenType.LessEqual else tokens.TokenType.Less);
            },
            else => {
                if (ascii.isDigit(c)) {
                    return self.number();
                }
                if (c == '"') {
                    return self.string(diagnostic);
                }
                if (ascii.isAlphabetic(c)) {
                    return self.identifier();
                }
                diagnostic.setContext(self, ScanError.UnknownCharacter, 1);
                return ScanError.UnknownCharacter;
            },
        }
    }

    fn number(self: *Scanner) tokens.Token {
        const start = self.current - 1;
        while (self.peek()) |c| {
            if (!ascii.isDigit(c)) break;
            _ = self.advance();
        } // Consume pre-dot numbers

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

    fn string(self: *Scanner, diagnostic: *Diagnostic) ScanError!tokens.Token {
        const start = self.current; // Ignore the starting '"'
        while (self.peek()) |c| {
            if (c == '"') {
                const token = self.makeToken(self.current - start, tokens.TokenType.String);
                _ = self.advance(); // Consume the closing quote.
                return token;
            }

            _ = self.advance();
        }

        diagnostic.setContext(self, ScanError.UnterminatedString, self.current - start);
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
        const length = self.current - start;
        // Check if keyword
        switch (self.source[start]) {
            'e' => if (self.checkRest("lse", start, length)) return self.makeToken(length, tokens.TokenType.Else),
            'f' => {
                if (length > 1) {
                    switch (self.source[start + 1]) {
                        'a' => if (self.checkRest("lse", start + 1, length - 1)) return self.makeToken(length, tokens.TokenType.False),
                        'o' => if (self.checkRest("r", start + 1, length - 1)) return self.makeToken(length, tokens.TokenType.For),
                        else => {},
                    }
                }
            },
            'i' => if (self.checkRest("f", start, length)) return self.makeToken(length, tokens.TokenType.If),
            'n' => if (self.checkRest("il", start, length)) return self.makeToken(length, tokens.TokenType.Nil),
            'p' => if (self.checkRest("rint", start, length)) return self.makeToken(length, tokens.TokenType.Print),
            't' => if (self.checkRest("rue", start, length)) return self.makeToken(length, tokens.TokenType.True),
            'w' => if (self.checkRest("hile", start, length)) return self.makeToken(length, tokens.TokenType.While),
            'v' => if (self.checkRest("ar", start, length)) return self.makeToken(length, tokens.TokenType.Var),
            else => {},
        }
        return self.makeToken(length, tokens.TokenType.Identifier);
    }

    fn checkRest(self: *Scanner, rest: []const u8, start: usize, length: usize) bool {
        if (length != rest.len + 1) return false;

        var i: usize = 1;
        for (rest) |c| {
            if (c != self.source[start + i]) {
                return false;
            }
            i += 1;
        }
        return true;
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

    fn match(self: *Scanner, expected: u8) bool {
        const current = self.peek() orelse return false;
        if (current != expected) return false;

        _ = self.advance();
        return true;
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
        }
        self.column += 1;
        self.current += 1;
        return cur;
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.source.len <= self.current;
    }

    // -------------------- Pretty Printing
    pub fn printErrors(diagnosticList: *const std.ArrayList(Diagnostic), source: []const u8) void {
        for (diagnosticList.items) |diagnostic| {
            diagnostic.report(source);
        }
    }

    pub fn printResults(tokenList: []tokens.Token, source: []const u8, writer: *std.Io.Writer) !void {
        try writer.print("==== Scan Results ====\n", .{});
        for (tokenList) |token| {
            try writer.print("zlox: Scanner: [line:{d:>3}|col:{d:>3}] {s} as {s}\n", .{ token.line, token.column, token.kind.toString(), token.getLexeme(source) });
        }
        try writer.flush();
    }
};
