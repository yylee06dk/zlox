const main = @import("../main.zig");
const std = @import("std");
const vm = @import("../vm.zig");

test "KNOWN ISSUE: multiline string column tracking underflows" {
    const source =
        \\print "first line
        \\second line";
    ;
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    try main.interpret(allocator, source, &machine, &output.writer);
    try std.testing.expectEqualStrings("first line\nsecond line\n", output.writer.buffered());
}
