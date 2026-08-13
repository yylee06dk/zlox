const values = @import("values.zig");
pub const TokenType = enum {
    Number,
    String,
    Plus,
    Minus,
    Star,
    Slash,
    LeftParen,
    RightParen,
    EOF,

    pub fn toString(self: TokenType) []const u8 {
        return switch (self) {
            .Number => "number",
            .String => "string",
            .Plus => "plus",
            .Minus => "minus",
            .Star => "star",
            .Slash => "slash",
            .LeftParen => "left paren",
            .RightParen => "right paren",
            .EOF => "EOF",
        };
    }
};

pub const Token = struct {
    kind: TokenType,
    start: usize,
    length: usize,
    line: u32,
    column: u32,

    pub fn getLexeme(self: Token, source: []const u8) []const u8 {
        if (self.kind == .EOF) {
            return "EOF";
        }
        return source[self.start .. self.start + self.length];
    }
};
