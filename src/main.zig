const std = @import("std");
const bcInfo = @import("bytecodeInfo.zig");
// const bc = @import("bytecode.zig");
const vm = @import("vm.zig");
const scan = @import("scanner.zig");
// const values = @import("values.zig");
const compile = @import("compiler.zig");

const Allocator = std.mem.Allocator;
const print = std.debug.print;

const DebugMode = false;
const DebugVM = DebugMode and true;
const DebugChunk = DebugMode and true;
const DebugGC = DebugMode and true;

pub const StdInterface = struct {
    stdin: *std.Io.Reader,
    stdout: *std.Io.Writer,
};

pub fn main(init: std.process.Init) !void {
    // Setting up machine used during the whole main-scope. The VM has the same life time as the main scope
    var machine = vm.VM.initSettings(DebugMode or DebugVM, init.gpa) catch |err| {
        fatalErrorReport(err);
        return;
    };
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
    var scanDiagnosticList: std.ArrayList(scan.Diagnostic) = .empty;
    defer scanDiagnosticList.deinit(init.gpa); // Diagnostic list lives within the run-scope.

    var scanner = scan.Scanner.init(source);
    const tokenList = try scanner.scanTokens(init.gpa, &scanDiagnosticList);
    defer init.gpa.free(tokenList); // Again, token List lives within the run

    // Debugging
    // if (scanDiagnosticList.items.len != 0) {
    //     scan.Scanner.printErrors(&scanDiagnosticList, source);
    // } // We proceed if the scan result is still messy
    // try scan.Scanner.printResults(tokenList, source, writer);

    // Compiler setup
    var compileDiagnostic = compile.Compiler.Diagnostic{};
    var compiler = try compile.Compiler.init(source, tokenList, machine, init.gpa);
    defer compiler.deinit(init.gpa);
    var chunk = compiler.compileOwnedChunk(init.gpa, &compileDiagnostic) catch |err| switch (err) {
        error.ParseFailed => {
            compileDiagnostic.report(source);
            return;
        },
        else => return err, // Fatal errors can just be propagated
    } orelse return; // Nothing to compile.
    defer chunk.deinit(init.gpa);
    if (DebugMode or DebugChunk) {
        try chunk.printChunk("debugging :)", writer);
    }

    // VM setup
    var vmDiagnostic = vm.VM.Diagnostic{};
    machine.setChunk(&chunk);
    machine.execute(writer, init.gpa, &vmDiagnostic) catch |err| switch (err) {
        error.RuntimeError, error.CompileError => {
            vmDiagnostic.report();
            return;
        },
        else => return err, // Fatal errors can just be propagated
    };
    if (DebugMode or DebugGC) {
        try writer.print("==== GC state ====\n{f}\n", .{machine.gcAlloc});
    }
    try writer.flush();
}
