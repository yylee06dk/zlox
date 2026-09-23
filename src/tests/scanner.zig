const std = @import("std");

const scanner = @import("../scanner.zig");
const tokens = @import("../tokens.zig");

fn checkKinds(source: []const u8, expected: []const tokens.TokenType) !void {
    const allocator = std.testing.allocator;
    var diagnostics: std.ArrayList(scanner.Diagnostic) = .empty;
    defer diagnostics.deinit(allocator);

    var lexer = scanner.Scanner.init(source);
    const actual = try lexer.scanTokens(allocator, &diagnostics);
    defer allocator.free(actual);

    try std.testing.expectEqual(@as(usize, 0), diagnostics.items.len);
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expectedKind, actualToken| {
        try std.testing.expectEqual(expectedKind, actualToken.kind);
    }
}

test "scanner boundary: tokenizes operators, literals, punctuation, and keywords" {
    try checkKinds(
        "( ) { } + - * / ! != = == > >= < <= ; , 12 3.5 \"text\" name true false nil print var if else while for fun return",
        &.{
            .LeftParen, .RightParen,   .LeftBrace, .RightBrace,
            .Plus,      .Minus,        .Star,      .Slash,
            .Bang,      .BangEquals,   .Equals,    .EqualEquals,
            .Greater,   .GreaterEqual, .Less,      .LessEqual,
            .Semicolon, .Comma,        .Number,    .Number,
            .String,    .Identifier,   .True,      .False,
            .Nil,       .Print,        .Var,       .If,
            .Else,      .While,        .For,       .Fun,
            .Return,    .EOF,
        },
    );
}

test "scanner boundary: preserves lexemes and source positions" {
    const source =
        \\var first = "hello";
        \\    print first;
    ;
    const allocator = std.testing.allocator;
    var diagnostics: std.ArrayList(scanner.Diagnostic) = .empty;
    defer diagnostics.deinit(allocator);

    var lexer = scanner.Scanner.init(source);
    const actual = try lexer.scanTokens(allocator, &diagnostics);
    defer allocator.free(actual);

    try std.testing.expectEqual(@as(usize, 0), diagnostics.items.len);
    try std.testing.expectEqualStrings("var", actual[0].getLexeme(source));
    try std.testing.expectEqual(@as(usize, 1), actual[0].line);
    try std.testing.expectEqual(@as(usize, 1), actual[0].column);
    try std.testing.expectEqualStrings("\"hello\"", actual[3].getLexeme(source));
    try std.testing.expectEqualStrings("print", actual[5].getLexeme(source));
    try std.testing.expectEqual(@as(usize, 2), actual[5].line);
    try std.testing.expectEqual(@as(usize, 5), actual[5].column);
}

test "scanner boundary: records an unknown character and continues" {
    const source = "print @ 1;";
    const allocator = std.testing.allocator;
    var diagnostics: std.ArrayList(scanner.Diagnostic) = .empty;
    defer diagnostics.deinit(allocator);

    var lexer = scanner.Scanner.init(source);
    const actual = try lexer.scanTokens(allocator, &diagnostics);
    defer allocator.free(actual);

    try std.testing.expectEqual(@as(usize, 1), diagnostics.items.len);
    try std.testing.expectEqualStrings("UnknownCharacter", @errorName(diagnostics.items[0].errorType));
    try std.testing.expectEqualStrings("@", diagnostics.items[0].getLexeme(source));
    try std.testing.expectEqual(@as(usize, 1), diagnostics.items[0].line);
    try std.testing.expectEqual(@as(usize, 7), diagnostics.items[0].column);
    const actualKinds = [_]tokens.TokenType{ actual[0].kind, actual[1].kind, actual[2].kind, actual[3].kind };
    try std.testing.expectEqualSlices(tokens.TokenType, &.{ .Print, .Number, .Semicolon, .EOF }, &actualKinds);
}

test "scanner boundary: reports an unterminated string without leaking" {
    const source = "\"unfinished";
    const allocator = std.testing.allocator;
    var diagnostics: std.ArrayList(scanner.Diagnostic) = .empty;
    defer diagnostics.deinit(allocator);

    var lexer = scanner.Scanner.init(source);
    const actual = try lexer.scanTokens(allocator, &diagnostics);
    defer allocator.free(actual);

    try std.testing.expectEqual(@as(usize, 1), diagnostics.items.len);
    try std.testing.expectEqualStrings("UnterminatedString", @errorName(diagnostics.items[0].errorType));
    try std.testing.expectEqualStrings("unfinished", diagnostics.items[0].getLexeme(source));
    try std.testing.expectEqual(@as(usize, 1), actual.len);
    try std.testing.expectEqual(tokens.TokenType.EOF, actual[0].kind);
}
