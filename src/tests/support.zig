const std = @import("std");

const app = @import("../main.zig");
const vm = @import("../vm.zig");

pub fn checkOutput(source: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    printCase(source, expected);
    try app.interpret(allocator, source, &machine, &output.writer);

    const actual = output.writer.buffered();
    std.debug.print("    actual output:\n{s}", .{actual});
    try std.testing.expectEqualStrings(expected, actual);
    try expectCleanExecution(&machine);
}

pub fn checkSession(submissions: []const []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    std.debug.print("    session submissions:\n", .{});
    for (submissions, 0..) |source, index| {
        std.debug.print("      {d}: {s}\n", .{ index + 1, source });
        try app.interpret(allocator, source, &machine, &output.writer);
        try expectCleanExecution(&machine);
    }

    const actual = output.writer.buffered();
    std.debug.print("    expected output:\n{s}", .{expected});
    std.debug.print("    actual output:\n{s}", .{actual});
    try std.testing.expectEqualStrings(expected, actual);
}

pub fn checkRuntimeError(source: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    std.debug.print("    runtime-error source:\n{s}\n", .{source});
    try std.testing.expectError(
        error.RuntimeError,
        app.interpret(allocator, source, &machine, &output.writer),
    );
}

pub fn checkRuntimeRecovery(failingSource: []const u8, nextSource: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(false, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    std.debug.print("    failing submission:\n{s}\n", .{failingSource});
    try std.testing.expectError(
        error.RuntimeError,
        app.interpret(allocator, failingSource, &machine, &output.writer),
    );

    output.clearRetainingCapacity();
    std.debug.print("    recovery submission:\n{s}\n", .{nextSource});
    try app.interpret(allocator, nextSource, &machine, &output.writer);

    const actual = output.writer.buffered();
    std.debug.print("    expected output:\n{s}", .{expected});
    std.debug.print("    actual output:\n{s}", .{actual});
    try std.testing.expectEqualStrings(expected, actual);
    try expectCleanExecution(&machine);
}

fn expectCleanExecution(machine: *const vm.VM) !void {
    try std.testing.expectEqual(@as(usize, 0), machine.frameCount);
    try std.testing.expectEqual(@as(usize, 0), machine.stack.length);
}

fn printCase(source: []const u8, expected: []const u8) void {
    std.debug.print("    source:\n{s}\n", .{source});
    std.debug.print("    expected output:\n{s}", .{expected});
}
