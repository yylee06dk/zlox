const std = @import("std");
const bc = @import("bytecode.zig");
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

    pub fn printByteCodeList(self: ByteCodeInfo, name: []const u8, writer: *std.Io.Writer) !void {
        var ip: usize = 0; // instruction pointer
        var curLine: usize = 0;
        try writer.print("==== {s} ====\n", .{name});
        while (ip < self.byteCodeList.items.len) {
            curLine = self.lineList.items[ip];
            const offset = try self.printSingleInstruction(ip, writer, curLine);
            ip += offset;
        }
    }

    fn printSingleInstruction(self: *const ByteCodeInfo, ip: usize, writer: *std.Io.Writer, curLine: usize) !usize {
        const curCode: bc.opCode = @enumFromInt(self.byteCodeList.items[ip]);

        var offset: usize = 0;
        try writer.print("{d:0>4} | {d:>4} : ", .{ ip, curLine });
        switch (curCode) {
            .ReturnOp => {
                offset = 1;
                try writer.print("{s}\n", .{curCode.toString()});
            },
        }

        return offset;
    }
};
