const std = @import("std");
const opCode = @import("opCode.zig");
const Code = std.ArrayList(u8);
const Line = std.ArrayList(usize);
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const ByteCodeInfo = struct {
    // Struct fields
    byteCodeList: Code,
    lineList: Line,

    // Constructor
    pub fn init() ByteCodeInfo {
        return .{
            .byteCodeList = .empty,
            .lineList = .empty,
        };
    }

    pub fn deinit(self: *ByteCodeInfo, alloc: Allocator) void {
        self.byteCodeList.deinit(alloc);
        self.lineList.deinit(alloc);
    }

    pub fn writeCode(self: *ByteCodeInfo, alloc: Allocator, code: u8, line: usize) !void {
        try self.byteCodeList.append(alloc, code);
        try self.lineList.append(alloc, line);
    }

    pub fn printPretty(self: ByteCodeInfo, name: []const u8) void {
        var prevLine: usize = 0;
        print("==== {s} ====\n", .{name});
        for (self.byteCodeList.items, 0..) |item, idx| {
            const curLine = self.lineList.items[idx];
            if (curLine == prevLine) {
                print("line:    |  {}\n", .{item});
            } else {
                prevLine = curLine;
                print("line: {d:0>4}  {}\n", .{ self.lineList.items[idx], item });
            }
        }
    }
};
