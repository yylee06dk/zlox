const main = @import("../main.zig");
const std = @import("std");
const vm = @import("../vm.zig");

fn checkEndToEndSucceed(src: []const u8, expect: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try main.interpret(allocator, src, &machine, &output.writer);

    const actual = output.writer.buffered();
    std.testing.expectEqualStrings(expect, actual) catch |err| {
        std.debug.print("    expect output:\n{s}", .{expect});
        std.debug.print("    actual output:\n{s}", .{actual});
        return err;
    };
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

test "ETE: basic arithmetic" {
    try checkEndToEndSucceed("print 1 + 2 * 3;", "7\n");
}

test "ETE: variable shadowing" {
    try checkEndToEndSucceed(
        \\{
        \\    var message = "outside";
        \\    {
        \\        var message = "inside";
        \\        print message;
        \\    }
        \\    print message;
        \\}
    , "inside\noutside\n");
}

test "ETE: local variable changed in multiple scope" {
    try checkEndToEndSucceed(
        \\{
        \\    var message = "Hello";
        \\    {
        \\        print message;
        \\        message = "World";
        \\        print message;
        \\    }
        \\    print message;
        \\}
    , "Hello\nWorld\nWorld\n");
}

test "ETE: basic for-loop" {
    try checkEndToEndSucceed(
        \\for (var i = 0; i < 4; i = i + 1) print i;
    ,
        "0\n1\n2\n3\n",
    );
}

test "ETE: returning functions" {
    try checkEndToEndSucceed(
        \\fun add(a, b) {
        \\    return a + b;
        \\}
        \\print add(20, 22);
    ,
        "42\n",
    );
}

test "ETE: string interning & string concat" {
    try checkEndToEndSucceed(
        \\var left = "hel";
        \\var right = "lo";
        \\print left + right;
        \\print (left + right) == "hello";
    , "hello\ntrue\n");
}

// test "end-to-end REPL boundary: globals persist across successful submissions" {
//     try support.checkSession(
//         &.{
//             "var answer = 40;",
//            "answer = answer + 2;",
//            "print answer;",
//        },
//        "42\n",
//    );
//}
//
//test "end-to-end regression: a failed submission releases all owned allocations" {
//    try support.checkRuntimeError("print missing;");
//}
//
//test "end-to-end REPL boundary: execution recovers after a runtime error" {
//    try support.checkRuntimeRecovery(
//        "print 1 + true;",
//        "print 42;",
//        "42\n",
//    );
//}
//
