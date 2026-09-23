const std = @import("std");

const bc = @import("../bytecode.zig");
const compiler = @import("../compiler.zig");
const objects = @import("../objects.zig");
const scanner = @import("../scanner.zig");
const vm = @import("../vm.zig");

const Compiled = struct {
    machine: vm.VM,
    function: *objects.Object.Function,

    fn deinit(self: *Compiled, allocator: std.mem.Allocator) void {
        self.machine.deinit(allocator);
    }
};

fn compile(source: []const u8) !Compiled {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    errdefer machine.deinit(allocator);

    var scanDiagnostics: std.ArrayList(scanner.Diagnostic) = .empty;
    defer scanDiagnostics.deinit(allocator);
    var lexer = scanner.Scanner.init(source);
    const tokenList = try lexer.scanTokens(allocator, &scanDiagnostics);
    defer allocator.free(tokenList);
    try std.testing.expectEqual(@as(usize, 0), scanDiagnostics.items.len);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    var diagnostic: compiler.Compiler.Diagnostic = .{};
    var instance = try compiler.Compiler.init(source, tokenList, &machine, .Script, 0, null, null, allocator);
    defer instance.deinit(allocator);

    const function = (try instance.compileOwnedFunctionObj(allocator, &diagnostic, &output.writer)) orelse return error.NothingCompiled;
    return .{ .machine = machine, .function = function };
}

fn instructionWidth(op: bc.opCode) usize {
    return switch (op) {
        .ReturnOp,
        .NegateOp,
        .AddOp,
        .SubOp,
        .MultOp,
        .DivOp,
        .EqOp,
        .NeqOp,
        .LessOp,
        .GreatOp,
        .LeqOp,
        .GeqOp,
        .PrintOp,
        .PopOp,
        .NilOp,
        => 1,
        .ConstantOp,
        .DefineGlobalOp,
        .GetGlobalOp,
        .SetGlobalOp,
        .DefineLocalOp,
        .GetLocalOp,
        .SetLocalOp,
        .CallOp,
        => 2,
        .JumpIfFalseOp, .JumpOp, .LoopOp => 3,
    };
}

fn decode(allocator: std.mem.Allocator, code: []const u8) ![]bc.opCode {
    var decoded: std.ArrayList(bc.opCode) = .empty;
    errdefer decoded.deinit(allocator);

    var ip: usize = 0;
    while (ip < code.len) {
        const op: bc.opCode = @enumFromInt(code[ip]);
        try decoded.append(allocator, op);
        ip += instructionWidth(op);
    }
    return decoded.toOwnedSlice(allocator);
}

fn checkOpcodes(source: []const u8, expected: []const bc.opCode) !void {
    const allocator = std.testing.allocator;
    var result = try compile(source);
    defer result.deinit(allocator);

    const actual = try decode(allocator, result.function.chunk.codeSlice);
    defer allocator.free(actual);

    std.debug.print("    source: {s}\n", .{source});
    std.debug.print("    expected opcodes: {any}\n", .{expected});
    std.debug.print("    actual opcodes:   {any}\n", .{actual});
    try std.testing.expectEqualSlices(bc.opCode, expected, actual);
}

test "compiler boundary: print consumes its expression without an extra pop" {
    try checkOpcodes("print 1;", &.{ .ConstantOp, .PrintOp });
}

test "compiler boundary: expression statements explicitly discard their value" {
    try checkOpcodes("1 + 2;", &.{ .ConstantOp, .ConstantOp, .AddOp, .PopOp });
}

test "compiler boundary: local declarations, reads, and scope cleanup use local opcodes" {
    try checkOpcodes(
        "{ var local = 1; print local; }",
        &.{ .ConstantOp, .DefineLocalOp, .GetLocalOp, .PrintOp, .PopOp },
    );
}

test "compiler boundary: while emits a conditional exit and backward edge" {
    var result = try compile("var i = 0; while (i < 2) i = i + 1;");
    defer result.deinit(std.testing.allocator);

    const actual = try decode(std.testing.allocator, result.function.chunk.codeSlice);
    defer std.testing.allocator.free(actual);

    try std.testing.expect(std.mem.indexOfScalar(bc.opCode, actual, .JumpIfFalseOp) != null);
    try std.testing.expect(std.mem.indexOfScalar(bc.opCode, actual, .LoopOp) != null);
    try std.testing.expect(std.mem.indexOfScalar(bc.opCode, actual, .SetGlobalOp) != null);
}

test "compiler boundary: function declaration and call encode arity" {
    var result = try compile("fun add(a, b) { return a + b; } print add(1, 2);");
    defer result.deinit(std.testing.allocator);

    const chunk = result.function.chunk;
    const actual = try decode(std.testing.allocator, chunk.codeSlice);
    defer std.testing.allocator.free(actual);

    try std.testing.expect(std.mem.indexOfScalar(bc.opCode, actual, .DefineGlobalOp) != null);
    const callIndex = std.mem.indexOfScalar(bc.opCode, actual, .CallOp) orelse return error.MissingCall;

    var byteIndex: usize = 0;
    var decodedIndex: usize = 0;
    while (decodedIndex < callIndex) : (decodedIndex += 1) {
        byteIndex += instructionWidth(actual[decodedIndex]);
    }
    try std.testing.expectEqual(@as(u8, 2), chunk.codeSlice[byteIndex + 1]);

    var foundFunction = false;
    for (chunk.constantSlice) |constant| {
        if (constant.asFunction()) |function| {
            foundFunction = true;
            try std.testing.expectEqual(@as(u8, 2), function.arity);
        }
    }
    try std.testing.expect(foundFunction);
}

test "compiler boundary: malformed initializer returns a structured parse failure" {
    const source = "var broken = ;";
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    var scanDiagnostics: std.ArrayList(scanner.Diagnostic) = .empty;
    defer scanDiagnostics.deinit(allocator);
    var lexer = scanner.Scanner.init(source);
    const tokenList = try lexer.scanTokens(allocator, &scanDiagnostics);
    defer allocator.free(tokenList);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var diagnostic: compiler.Compiler.Diagnostic = .{};
    var instance = try compiler.Compiler.init(source, tokenList, &machine, .Script, 0, null, null, allocator);
    defer instance.deinit(allocator);

    try std.testing.expectError(
        error.ParseFailed,
        instance.compileOwnedFunctionObj(allocator, &diagnostic, &output.writer),
    );
    try std.testing.expectEqualStrings("Expected preceding expression at", diagnostic.message);
    try std.testing.expectEqualStrings(";", diagnostic.token.getLexeme(source));
}
