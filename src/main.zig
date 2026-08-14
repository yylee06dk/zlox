const std = @import("std");
const bc = @import("bytecode.zig");
const scan = @import("scanner.zig");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const BootUpError = error{
    WrongCommandLine,
};

pub fn main(init: std.process.Init) !void {
    // Debug allocator used for allocating things in whole main-level scope

    var argsIterator = init.minimal.args.iterate();
    _ = argsIterator.skip(); // skip binary name

    if (argsIterator.next()) |filePath| {
        if (argsIterator.skip()) { // Check for additional arguments
            print("Usage: <binary> <file_path>\n", .{});
            return BootUpError.WrongCommandLine;
        }

        try runFile(init, filePath);
        return;
    }

    try runREPL(init);
    return;
}

fn runFile(init: std.process.Init, path: []const u8) !void {
    var alloc = init.gpa;

    const source = std.Io.Dir.cwd().readFileAlloc(init.io, path, alloc, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.StreamTooLong => {
            print("Too long file given.\n", .{});
            return err;
        },
        else => return err,
    };
    defer alloc.free(source);
    // stdout init
    var stdoutBuf: [2048]u8 = undefined;
    var stdoutWriter = std.Io.File.stdout().writerStreaming(init.io, &stdoutBuf);
    var stdout = &stdoutWriter.interface;
    defer stdout.flush() catch {};

    // Scanner init
    var scanner = scan.Scanner.init(source);
    var diagnosticList: std.ArrayList(scan.Diagnostic) = .empty;
    const tokenList = try scanner.scanTokens(alloc, &diagnosticList);
    defer alloc.free(tokenList);
    defer diagnosticList.deinit(alloc);

    for (diagnosticList.items, 0..) |diagnostic, idx| {
        print("{d:>3}: At line {d:>3}, column: {d:>3} | {} happened at {s}\n", .{ idx + 1, diagnostic.line, diagnostic.column, diagnostic.errorType, diagnostic.getLexeme(source) });
    }

    for (tokenList, 0..) |token, idx| {
        try stdout.print("{d:>3}: {s:>12} at line {d:>3}, column: {d:>3} | {s}\n", .{ idx + 1, token.kind.toString(), token.line, token.column, token.getLexeme(source) });
    }
}

fn runREPL(init: std.process.Init) !void {
    var alloc = init.gpa;
    // REPL
    var stdinBuf: [1024]u8 = undefined;
    var stdinReader = std.Io.File.stdin().readerStreaming(
        init.io,
        &stdinBuf,
    );
    const stdin = &stdinReader.interface;

    var stdoutBuf: [1024]u8 = undefined;
    var stdoutWriter = std.Io.File.stdout().writerStreaming(init.io, &stdoutBuf);
    var stdout = &stdoutWriter.interface;
    defer stdout.flush() catch {};

    while (true) {
        try stdout.writeAll("|>> ");
        try stdout.flush();

        const line = stdin.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                print("Input line too long.\n", .{});
                return err;
            },
            else => return err,
        } orelse break; // Nothing more to read (EOF met + nothing left in stream)

        if (line.len == 0) continue; // Nothing given, but EOF not met

        var scanner = scan.Scanner.init(line);
        var diagnosticList: std.ArrayList(scan.Diagnostic) = .empty;
        const tokenList = try scanner.scanTokens(alloc, &diagnosticList);
        defer alloc.free(tokenList);
        defer diagnosticList.deinit(alloc);

        for (diagnosticList.items, 0..) |diagnostic, idx| {
            print("{d:>3}: At line {d:>3}, column: {d:>3} | {} happened at {s}\n", .{ idx + 1, diagnostic.line, diagnostic.column, diagnostic.errorType, diagnostic.getLexeme(line) });
        }

        for (tokenList, 0..) |token, idx| {
            try stdout.print("{d:>3}: {s:>12} at line {d:>3}, column: {d:>3} | {s}\n", .{ idx + 1, token.kind.toString(), token.line, token.column, token.getLexeme(line) });
        }
    }
}
