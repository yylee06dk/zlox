const std = @import("std");
const bc = @import("bytecode.zig");
const scan = @import("scanner.zig");
const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    var debugAllocator = std.heap.DebugAllocator(.{}){};
    const alloc = debugAllocator.allocator();
    defer {
        const leakCheck = debugAllocator.deinit();
        if (leakCheck == .leak) {
            print("Memory leak detected\n", .{});
        }
    }

    // REPL
    var stdinBuf: [1024]u8 = undefined;
    var stdinReader = std.Io.File.stdout().readerStreaming(
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

        const line = try stdin.takeDelimiter('\n') orelse break;

        if (line.len == 0) continue;

        var scanner = scan.Scanner.init(line);
        const tokenList = try scanner.scanTokens(alloc);
        defer alloc.free(tokenList);

        for (tokenList, 0..) |token, idx| {
            try stdout.print("{d:>3}: {s:>12} at line {d:>3}, column: {d:>3} | {s}\n", .{ idx + 1, token.kind.toString(), token.line, token.column, token.getLexeme(line) });
        }
    }

    return;
}
