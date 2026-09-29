const std = @import("std");
const bcInfo = @import("bytecodeInfo.zig");
// const bc = @import("bytecode.zig");
const vm = @import("vm.zig");
const scan = @import("scanner.zig");
// const values = @import("values.zig");
const compile = @import("compiler.zig");

const clap = @import("clap");

const Allocator = std.mem.Allocator;
const print = std.debug.print;

//const DebugVM = DebugMode and true;
//const DebugChunk = DebugMode and true;
//const DebugGC = DebugMode and true;

pub const StdInterface = struct {
    stdin: *std.Io.Reader,
    stdout: *std.Io.Writer,
};

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display help and exit.
        \\-d, --debug            Enable all debug output.
        \\-b, --bytecode         Display bytecode. Also enabled by --debug.
        \\-v, --vmTrace          Display VM execution traces. Also enabled by --debug.
        \\-g, --gcState          Display GC state. Also enabled by --debug.
        \\-s, --stressGC         Stress GC to run after every allocation. Not enabled in --debug
        \\<str>
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        std.debug.print(
            \\Usage: zlox [options] [file]
            \\
            \\Options:
            \\  -h, --help      Show this help
            \\  -d, --debug     Enable all debug output
            \\  -b, --bytecode  Display bytecode
            \\  -v, --vmTrace   Trace VM execution
            \\  -g, --gcState   Display GC state
            \\  -s, --stressGC  GC boots every time allocation happens
            \\
        , .{});
        return;
    }
    const debugSettings: vm.VM.DebugSettings = .{
        .all = res.args.debug != 0,
        .bytecode = res.args.bytecode != 0,
        .vmTrace = res.args.vmTrace != 0,
        .gcState = res.args.gcState != 0,
        .stressGC = res.args.stressGC != 0,
    };
    // Setting up machine used during the whole main-scope. The VM has the same life time as the main scope
    var machine = vm.VM.initSettings(debugSettings, init.gpa) catch |err| {
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
    if (res.positionals[0]) |s| {
        runFile(init, s, &machine, &stdInterface) catch |err| {
            fatalErrorReport(err);
        };
        return;
    }

    runREPL(init, &machine, &stdInterface) catch |err| {
        fatalErrorReport(err);
    };
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

    interpret(
        init.gpa,
        source,
        machine,
        interface.stdout,
    ) catch |err| switch (err) {
        error.RuntimeError, error.CompileError => return,
        else => return err,
    };
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

        interpret(init.gpa, line, machine, interface.stdout) catch |err| switch (err) {
            error.RuntimeError, error.CompileError => {
                break;
            },
            else => return err, // Fatal errors can just be propagated
        };
    }
}

pub fn interpret(alloc: Allocator, source: []const u8, machine: *vm.VM, writer: *std.Io.Writer) !void {
    // Scanner setup
    var scanDiagnosticList: std.ArrayList(scan.Diagnostic) = .empty;
    defer scanDiagnosticList.deinit(alloc); // Diagnostic list lives within the run-scope.

    var scanner = scan.Scanner.init(source);
    const tokenList = try scanner.scanTokens(alloc, &scanDiagnosticList);
    defer alloc.free(tokenList); // Again, token List lives within the run

    // Debugging
    // if (scanDiagnosticList.items.len != 0) {
    //     scan.Scanner.printErrors(&scanDiagnosticList, source);
    // } // We proceed if the scan result is still messy
    // try scan.Scanner.printResults(tokenList, source, writer);

    // Compiler setup
    var compileDiagnostic = compile.Compiler.Diagnostic{};
    var compiler = try compile.Compiler.init(source, tokenList, machine, compile.Compiler.CompileType.Script, 0, null, null, alloc);
    defer compiler.deinit(alloc);
    const scriptPtr = compiler.compileOwnedFunctionObj(alloc, &compileDiagnostic, writer) catch |err| switch (err) {
        error.ParseFailed => {
            compileDiagnostic.report(source);
            return;
        },
        else => return err, // Fatal errors can just be propagated
    } orelse return; // Nothing to compile.
    // Memory controlled by GC
    if (machine.debugSettings.bytecodeEnabled()) {
        try writer.print("{f}", .{std.fmt.alt(scriptPtr.*, .formatTotal)});
    }

    // VM setup
    var vmDiagnostic = vm.VM.Diagnostic{};
    try machine.setTargetFunction(scriptPtr, alloc);
    machine.execute(writer, alloc, &vmDiagnostic) catch |err| {
        try writer.flush();
        switch (err) {
            error.RuntimeError => {
                vmDiagnostic.report();
                return err;
            },
            error.CompileError => {
                vmDiagnostic.reportFatal();
                return err;
            },
            else => return err, // Fatal errors can just be propagated
        }
    };
    if (machine.debugSettings.gcStateEnabled()) {
        try writer.print("==== GC state ====\n{f}\n", .{machine.gcAlloc});
    }
    try writer.flush();
}
