const std = @import("std");
const vm = @import("../vm.zig");
const main = @import("../main.zig");

fn checkSessionSucceed(submissions: []const []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    for (submissions) |source| {
        try main.interpret(allocator, source, &machine, &output.writer);

        // Check clean execution
        std.testing.expectEqual(@as(usize, 0), machine.frameCount) catch |err| {
            std.debug.print("    Dirty cleanup: FrameCount not 0", .{});
            return err;
        };
        std.testing.expectEqual(@as(usize, 0), machine.stack.length) catch |err| {
            std.debug.print("    Dirty cleanup: Stack length not 0", .{});
            return err;
        };
    }

    const actual = output.writer.buffered();
    std.testing.expectEqualStrings(expected, actual) catch |err| {
        std.debug.print("    expected output:\n{s}", .{expected});
        std.debug.print("    actual output:\n{s}", .{actual});
        return err;
    };
}

fn checkSessionRecovery(failingSource: []const u8, nextSource: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    try std.testing.expectError(
        error.RuntimeError,
        main.interpret(allocator, failingSource, &machine, &output.writer),
    );

    output.clearRetainingCapacity();
    try main.interpret(allocator, nextSource, &machine, &output.writer);
    try std.testing.expectEqualStrings(expected, output.writer.buffered());
    try std.testing.expectEqual(@as(usize, 0), machine.frameCount);
    try std.testing.expectEqual(@as(usize, 0), machine.stack.length);
}

test "ETE session: globals persist across submissions" {
    try checkSessionSucceed(
        &.{
            "var answer = 40;",
            "answer = answer + 2;",
            "print answer;",
        },
        "42\n",
    );
}

test "ETE session: functions persist across submissions" {
    try checkSessionSucceed(
        &.{
            "fun addOne(value) { return value + 1; }",
            "print addOne(41);",
        },
        "42\n",
    );
}

test "ETE session: closures retain state across submissions" {
    try checkSessionSucceed(
        &.{
            "fun makeCounter() { var value = 40; fun next() { value = value + 1; return value; } return next; }",
            "var counter = makeCounter();",
            "print counter();",
            "print counter();",
        },
        "41\n42\n",
    );
}

test "ETE session: redeclaring a global replaces its value" {
    try checkSessionSucceed(
        &.{
            "var value = \"first\";",
            "var value = \"second\";",
            "print value;",
        },
        "second\n",
    );
}

test "ETE session: local shadowing does not replace a global" {
    try checkSessionSucceed(
        &.{
            "var value = \"global\";",
            "{ var value = \"local\"; print value; }",
            "print value;",
        },
        "local\nglobal\n",
    );
}

test "ETE session: closure observes later global assignment" {
    try checkSessionSucceed(
        &.{
            "var value = \"before\"; fun show() { print value; }",
            "value = \"after\";",
            "show();",
        },
        "after\n",
    );
}

test "ETE session: a function resolves a global declared later" {
    try checkSessionSucceed(
        &.{
            "fun callLater() { return later(); }",
            "fun later() { return 42; }",
            "print callLater();",
        },
        "42\n",
    );
}

test "ETE session: independent closures keep state between submissions" {
    try checkSessionSucceed(
        &.{
            "fun makeCounter() { var value = 0; fun next() { value = value + 1; return value; } return next; }",
            "var first = makeCounter(); var second = makeCounter();",
            "print first();",
            "print first(); print second();",
        },
        "1\n2\n1\n",
    );
}

test "ETE session: uninitialized global can be assigned later" {
    try checkSessionSucceed(
        &.{
            "var value;",
            "print value;",
            "value = 42;",
            "print value;",
        },
        "<nil>\n42\n",
    );
}

test "ETE session: interned strings compare across submissions" {
    try checkSessionSucceed(
        &.{
            "var stored = \"same\";",
            "print stored == \"same\";",
            "stored = \"s\" + \"ame\";",
            "print stored == \"same\";",
        },
        "true\ntrue\n",
    );
}

test "ETE session: execution recovers after a runtime error" {
    try checkSessionRecovery(
        "print 1 + true;",
        "print 42;",
        "42\n",
    );
}
