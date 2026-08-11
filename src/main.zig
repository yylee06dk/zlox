const std = @import("std");
const bc = @import("byteCode.zig");
const print = std.debug.print;

pub fn main() !void {
    var debugAllocator = std.heap.DebugAllocator(.{}){};
    const alloc = debugAllocator.allocator();
    defer {
        const leakCheck = debugAllocator.deinit();
        if (leakCheck == .leak) {
            print("Memory leak detected\n", .{});
        }
    }

    var bcInfo: bc.ByteCodeInfo = bc.ByteCodeInfo.init(alloc);
    defer bcInfo.deinit(alloc);

    var pbcInfo: *bc.ByteCodeInfo = &bcInfo;
    try pbcInfo.writeCode(alloc, 0, 1);
    try pbcInfo.writeCode(alloc, 1, 1);
    try pbcInfo.writeCode(alloc, 2, 1);

    bcInfo.printPretty("test");
    return;
}
