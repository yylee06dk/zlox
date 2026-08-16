const std = @import("std");
const bcInfo = @import("bytecodeInfo.zig");
const bc = @import("bytecode.zig");
const vm = @import("vm.zig");
const scan = @import("scanner.zig");
const values = @import("values.zig");

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

    try run(init, source, stdout);
}

fn runREPL(init: std.process.Init) !void {
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

        try run(init, line, stdout);
    }
}

fn run(init: std.process.Init, source: []const u8, writer: *std.Io.Writer) !void {
    var alloc = init.gpa;
    // Scanner -- start
    var diagnosticList: std.ArrayList(scan.Diagnostic) = .empty;
    defer diagnosticList.deinit(alloc);

    var scanner = scan.Scanner.init(source);
    const tokenList = try scanner.scanTokens(alloc, &diagnosticList);
    defer alloc.free(tokenList);

    // Debugging
    if (diagnosticList.items.len != 0) {
        scan.Scanner.printErrors(&diagnosticList, source);
    }
    try scan.Scanner.printResults(tokenList, source, writer);
    // Scanner -- end

    // the pipeline
    //
    // const bcInfo = compiler.compile(tokenList); --> Suppose errors are well dealt with
    // var virtualMachine = vm.VM.init(&bcInfo, false); -> ownership of bcInfo stays in the scope of `run` function
    //
    // try virtualMachine.run(); -> where all the magic happens.

    // Bytecode testing
    var bytecodeInfo = bcInfo.ByteCodeInfo.init();
    defer bytecodeInfo.deinit(alloc);

    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.ReturnOp), 1);

    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.ConstantOp), 2);
    const item = values.Value{ .number = 1.2 };
    const addr = try bytecodeInfo.addConstant(alloc, item);
    if (addr > std.math.maxInt(u8)) {
        unreachable; // Need to be changed! -- After implementing compiler step
    }
    try bytecodeInfo.writeCode(alloc, @intCast(addr), 2);
    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.ReturnOp), 3);
    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.NegateOp), 4);
    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.ReturnOp), 5);
    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.ConstantOp), 5);
    const item2 = values.Value{ .number = 1.3 };
    const addr2 = try bytecodeInfo.addConstant(alloc, item2);
    if (addr2 > std.math.maxInt(u8)) {
        unreachable; // Need to be changed! -- After implementing compiler step
    }
    try bytecodeInfo.writeCode(alloc, @intCast(addr2), 7);
    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.AddOp), 5);
    try bytecodeInfo.writeCode(alloc, @intFromEnum(bc.opCode.ReturnOp), 5);

    // VM -- start
    var VM = vm.VM.init(&bytecodeInfo, true);
    try VM.execute(writer);

    try bytecodeInfo.printByteCodeList("test", writer);
}
