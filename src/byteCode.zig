const std = @import("std");
const opCodeType = @import("opCode.zig").opCode;
const Code = std.ArrayList(u8);
const Line = std.ArrayList(u16);
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const ByteCodeInfo = struct {
    // Struct fields
    byteCodeList: Code,
    lineList: Line,

    // Constructor
    pub fn init(alloc: Allocator) ByteCodeInfo {
        var codeList: Code = .empty;
        errdefer codeList.deinit(alloc);
        var lineList: std.ArrayList(u16) = .empty;
        errdefer lineList.deinit(alloc);
        print("INIT:\ncodeListstart:{*}\nlineListStart:{*}\n", .{ codeList.items, lineList.items });

        return .{
            .byteCodeList = codeList,
            .lineList = lineList,
        };
    }

    pub fn deinit(self: ByteCodeInfo, alloc: Allocator) void {
        var bcList = self.byteCodeList;
        var lineList = self.lineList;
        bcList.deinit(alloc);
        lineList.deinit(alloc);
        return;
    }

    pub fn writeCode(self: *ByteCodeInfo, alloc: Allocator, code: u8, line: u16) !void {
        var bcList = self.byteCodeList;
        var lineList = self.lineList;
        try bcList.append(alloc, code);
        try lineList.append(alloc, line);
        return;
    }

    pub fn printPretty(self: ByteCodeInfo, name: []const u8) void {
        print("==== {s} ====\n", .{name});
        for (self.byteCodeList.items, 0..) |item, idx| {
            print("{d}  {}", .{ self.lineList.items[idx], item });
        }
    }
};
