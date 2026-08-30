const std = @import("std");
const values = @import("values.zig");

pub const TokenType = enum {
    Number,
    String,
    Identifier,
    Plus,
    Bang,
    Minus,
    Star,
    Slash,
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Equals,
    EqualEquals,
    BangEquals,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    Semicolon,
    True,
    False,
    Nil,
    Print,
    Var,
    EOF,

    pub fn toString(self: TokenType) []const u8 {
        return switch (self) {
            .Number => "number",
            .String => "string",
            .Identifier => "identifier",
            .Plus => "plus",
            .Bang => "!",
            .Minus => "minus",
            .Star => "star",
            .Slash => "slash",
            .LeftParen => "left paren",
            .RightParen => "right paren",
            .LeftBrace => "left brace",
            .RightBrace => "right brace",
            .Equals => "=",
            .EqualEquals => "==",
            .BangEquals => "!=",
            .Greater => ">",
            .GreaterEqual => ">=",
            .Less => "<",
            .LessEqual => "<=",
            .Semicolon => ";",
            .True => "true",
            .False => "false",
            .Nil => "<nil>",
            .Print => "print",
            .Var => "var",
            .EOF => "EOF",
        };
    }
};

pub const Token = struct {
    kind: TokenType,
    start: usize,
    length: usize,
    line: usize,
    column: usize,

    pub fn getLexeme(self: Token, source: []const u8) []const u8 {
        if (self.kind == .EOF) {
            return "EOF";
        }
        const checkString: usize = if (self.kind == .String) 1 else 0;
        return source[self.start - checkString .. self.start + self.length + checkString];
    }
};
