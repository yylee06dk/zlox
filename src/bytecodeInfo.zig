const std = @import("std");
const bc = @import("bytecode.zig");
const values = @import("values.zig");
const Code = std.ArrayList(u8);
const Line = std.ArrayList(usize);
const Values = std.ArrayList(values.Value);
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const t = std.debug.print;

pub const Chunk = struct {
    codeSlice: []u8,
    lineSlice: []usize,
    constantSlice: []values.Value,
    // Owns all the slices

    pub fn deinit(self: *Chunk, alloc: Allocator) void {
        alloc.free(self.codeSlice);
        alloc.free(self.lineSlice);
        alloc.free(self.constantSlice);
    }
};

pub const ByteCodeInfo = struct {
    // Struct fields
    byteCodeList: Code,
    lineList: Line,
    constantList: Values,

    // Constructor
    pub fn init() ByteCodeInfo {
        return .{ .byteCodeList = .empty, .lineList = .empty, .constantList = .empty };
    }

    pub fn deinit(self: *ByteCodeInfo, alloc: Allocator) Allocator.Error!Chunk {
        return .{
            .codeSlice = try self.byteCodeList.toOwnedSlice(alloc),
            .lineSlice = try self.lineList.toOwnedSlice(alloc),
            .constantSlice = try self.constantList.toOwnedSlice(alloc),
        };
    }

    pub fn writeCode(self: *ByteCodeInfo, alloc: Allocator, code: u8, line: usize) Allocator.Error!void {
        try self.byteCodeList.append(alloc, code);
        try self.lineList.append(alloc, line);
    }

    pub fn addConstant(self: *ByteCodeInfo, alloc: Allocator, item: values.Value) Allocator.Error!usize {
        try self.constantList.append(alloc, item);
        const addrIdx = self.constantList.items.len - 1;
        return addrIdx;
    }

    // ---------- Pretty printing
    pub fn printByteCodeList(self: ByteCodeInfo, name: []const u8, writer: *std.Io.Writer) !void {
        var ip: usize = 0; // instruction pointer
        var curLine: usize = 0;
        try writer.print("==== {s} ====\n", .{name});
        try writer.print("BYTE | LINE | --------\n", .{});
        while (ip < self.byteCodeList.items.len) {
            curLine = self.lineList.items[ip];
            const offset = try self.printSingleInstruction(ip, writer, curLine);
            ip += offset;
        }
    }

    fn printSingleInstruction(self: *const ByteCodeInfo, ip: usize, writer: *std.Io.Writer, curLine: usize) !usize {
        const curCode: bc.opCode = @enumFromInt(self.byteCodeList.items[ip]);

        try writer.print("{d:0>4} | {d:>4} : ", .{ ip, curLine });
        switch (curCode) {
            .ConstantOp => {
                const constant_idx = self.byteCodeList.items[ip + 1];
                const constant = self.constantList.items[constant_idx];
                try writer.print("{s} {d:>3} '{f}'\n", .{ curCode.toString(), constant_idx, constant });
                return 2;
            },
            .ReturnOp, .NegateOp, .AddOp, .SubOp, .MultOp, .DivOp => {
                try writer.print("{s}\n", .{curCode.toString()});
                return 1;
            },
        }
    }
};
