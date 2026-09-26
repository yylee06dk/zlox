const std = @import("std");

const bc = @import("../bytecode.zig");
const bytecodeInfo = @import("../bytecodeInfo.zig");
const objectStore = @import("../objectStore.zig");
const objects = @import("../objects.zig");
const values = @import("../values.zig");
const vm = @import("../vm.zig");

fn installScript(machine: *vm.VM, code: []const u8, constants: []const values.Value, allocator: std.mem.Allocator) !*objects.Object.Function {
    const ownedCode = try allocator.dupe(u8, code);
    errdefer allocator.free(ownedCode);

    const ownedLines = try allocator.alloc(usize, code.len);
    errdefer allocator.free(ownedLines);
    @memset(ownedLines, 1);

    const ownedConstants = try allocator.dupe(values.Value, constants);
    errdefer allocator.free(ownedConstants);

    const function = try allocator.create(objects.Object.Function);
    errdefer allocator.destroy(function);
    function.* = .{
        .chunk = bytecodeInfo.Chunk{
            .codeSlice = ownedCode,
            .lineSlice = ownedLines,
            .constantSlice = ownedConstants,
        },
        .name = null,
        .arity = 0,
    };
    try machine.gcAlloc.addAllocation(.{ .function = function }, @sizeOf(objects.Object.Function), allocator);
    return function;
}

fn executeChunk(code: []const u8, constants: []const values.Value, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    const function = try installScript(&machine, code, constants, allocator);
    try machine.setTargetFunction(function, allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var diagnostic: vm.VM.Diagnostic = .{};
    try machine.execute(&output.writer, allocator, &diagnostic);

    try std.testing.expectEqualStrings(expected, output.writer.buffered());
    try std.testing.expectEqual(@as(usize, 0), machine.stack.length);
    try std.testing.expectEqual(@as(usize, 0), machine.frameCount);
}

test "VM boundary: PrintOp consumes one constant and leaves a clean machine" {
    try executeChunk(
        &.{ @intFromEnum(bc.opCode.ConstantOp), 0, @intFromEnum(bc.opCode.PrintOp) },
        &.{.{ .number = 41 }},
        "41\n",
    );
}

test "VM boundary: AddOp consumes two operands and produces one result" {
    try executeChunk(
        &.{
            @intFromEnum(bc.opCode.ConstantOp), 0,
            @intFromEnum(bc.opCode.ConstantOp), 1,
            @intFromEnum(bc.opCode.AddOp),      @intFromEnum(bc.opCode.PrintOp),
        },
        &.{ .{ .number = 20 }, .{ .number = 22 } },
        "42\n",
    );
}

test "VM boundary regression: printing a trailing-allocation string uses its original pointer" {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    const string = try objectStore.makeString(
        "stable string",
        "stable string".len,
        &machine.gcAlloc,
        &machine.stringPool,
        allocator,
    );
    const function = try installScript(
        &machine,
        &.{ @intFromEnum(bc.opCode.ConstantOp), 0, @intFromEnum(bc.opCode.PrintOp) },
        &.{.{ .string = string }},
        allocator,
    );
    try machine.setTargetFunction(function, allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var diagnostic: vm.VM.Diagnostic = .{};
    try machine.execute(&output.writer, allocator, &diagnostic);

    try std.testing.expectEqualStrings("stable string\n", output.writer.buffered());
    try std.testing.expectEqual(@as(usize, 0), machine.stack.length);
    try std.testing.expectEqual(@as(usize, 0), machine.frameCount);
}

test "VM boundary: invalid operand types return a runtime diagnostic" {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    const function = try installScript(
        &machine,
        &.{
            @intFromEnum(bc.opCode.ConstantOp), 0,
            @intFromEnum(bc.opCode.ConstantOp), 1,
            @intFromEnum(bc.opCode.AddOp),
        },
        &.{ .{ .number = 1 }, .{ .boolean = true } },
        allocator,
    );
    try machine.setTargetFunction(function, allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var diagnostic: vm.VM.Diagnostic = .{};
    try std.testing.expectError(error.RuntimeError, machine.execute(&output.writer, allocator, &diagnostic));
    try std.testing.expectEqualStrings(
        "Operands of operator '+' must both have type number or string",
        diagnostic.message,
    );
}
