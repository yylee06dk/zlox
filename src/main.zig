const std = @import("std");
const bcInfo = @import("bytecodeInfo.zig");
// const bc = @import("bytecode.zig");
const vm = @import("vm.zig");
const scan = @import("scanner.zig");
// const values = @import("values.zig");
const compile = @import("compiler.zig");

const Allocator = std.mem.Allocator;
const print = std.debug.print;

const DebugMode = true;

pub const StdInterface = struct {
    stdin: *std.Io.Reader,
    stdout: *std.Io.Writer,
};

pub fn main(init: std.process.Init) !void {
    // Setting up machine used during the whole main-scope. The VM has the same life time as the main scope
    var machine = vm.VM.initSettings(true);
    defer machine.deinit(init.gpa);

    // Setting up basic reader & writer interfaces
    var stdinBuf: [1024]u8 = undefined;
    var stdinReader = std.Io.File.stdin().readerStreaming(
        init.io,
        &stdinBuf,
    );
    const stdin = &stdinReader.interface;

    var stdoutBuf: [2048]u8 = undefined;
    var stdoutWriter = std.Io.File.stdout().writerStreaming(init.io, &stdoutBuf);
    const stdout = &stdoutWriter.interface;
    defer stdout.flush() catch |err| {
        fatalErrorReport(err);
    };

    var stdInterface = StdInterface{
        .stdin = stdin,
        .stdout = stdout,
    };

    // Generates unportable code (according to zig std documentation)
    var argsIterator = init.minimal.args.iterate();
    _ = argsIterator.skip(); // skip binary name

    if (argsIterator.next()) |filePath| {
        if (argsIterator.skip()) { // Check for additional arguments
            print("Usage: <binary> <file_path>\n", .{});
        }

        try runFile(init, filePath, &machine, &stdInterface);
        return;
    }

    try runREPL(init, &machine, &stdInterface);
    return;
}

fn fatalErrorReport(err: anyerror) void {
    print("zlox: FatalError: {s}\n", .{@errorName(err)});
}

fn runFile(init: std.process.Init, path: []const u8, machine: *vm.VM, interface: *StdInterface) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.StreamTooLong => {
            print("zlox: Input file too long.\n", .{});
            return;
        },
        else => return err, // All stdlib level fatal errors
    };
    defer init.gpa.free(source); // source lives all along this scope --> the whole running process is within its lifetime
    // stdout init

    try run(
        init,
        source,
        machine,
        interface.stdout,
    );
}

fn runREPL(init: std.process.Init, machine: *vm.VM, interface: *StdInterface) !void {
    while (true) {
        try interface.stdout.writeAll("|>> ");
        try interface.stdout.flush();
        // Fatal errors

        const line = interface.stdin.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                print("zlox: Input line too long.\n", .{});
                return;
            },
            else => return err, // Fatal errors
        } orelse break; // Nothing more to read (EOF met + nothing left in stream)

        if (line.len == 0) continue; // Nothing given, but EOF not met

        try run(init, line, machine, interface.stdout);
    }
}

fn run(init: std.process.Init, source: []const u8, machine: *vm.VM, writer: *std.Io.Writer) !void {
    // Scanner setup
    var diagnosticList: std.ArrayList(scan.Diagnostic) = .empty;
    defer diagnosticList.deinit(init.gpa); // Diagnostic list lives within the run-scope.

    var scanner = scan.Scanner.init(source);
    const tokenList = try scanner.scanTokens(init.gpa, &diagnosticList);
    defer init.gpa.free(tokenList); // Again, token List lives within the run

    // Debugging
    if (diagnosticList.items.len != 0) {
        scan.Scanner.printErrors(&diagnosticList, source);
    } // We proceed if the scan result is still messy
    try scan.Scanner.printResults(tokenList, source, writer);

    // Compiler setup
    var bytecodeInfo = bcInfo.ByteCodeInfo.init();
    defer bytecodeInfo.deinit(init.gpa); // Same lifetime with run

    var compiler = compile.Compiler.init(source, tokenList, &bytecodeInfo, machine);
    compiler.compile(init.gpa) catch |err| {
        //catch desired errors (compiler errors should be catched and reported at this level)
        return err; // Fatal errors can just be propagated
    };

    // debugging
    try bytecodeInfo.printByteCodeList("Result", writer);

    // VM setup
    machine.setByteCode(&bytecodeInfo);
    machine.execute(writer, init.gpa) catch |err| {
        // VM errors should be catched and handled
        return err; // Fatal errors can just be propagated
    };
    try writer.print("DEBUG:\n{f}\n", .{machine.gcAlloc});
}
