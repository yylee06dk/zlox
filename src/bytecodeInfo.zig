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

    pub fn printChunk(self: *const Chunk, name: []const u8, writer: *std.Io.Writer) !void {
        var ip: usize = 0; // instruction pointer
        var curLine: usize = 0;
        try writer.print("==== {s} ====\n", .{name});
        try writer.print("BYTE | LINE | --------\n", .{});
        while (ip < self.codeSlice.len) {
            curLine = self.lineSlice[ip];
            const offset = try self.printSingleInstruction(ip, writer, curLine);
            ip += offset;
        }
        try writer.print("==== {s} ====\n", .{name});
        try writer.flush();
    }

    fn printSingleInstruction(self: *const Chunk, ip: usize, writer: *std.Io.Writer, curLine: usize) !usize {
        const curCode: bc.opCode = @enumFromInt(self.codeSlice[ip]);

        try writer.print("{d:0>4} | {d:>4} : {s} ", .{ ip, curLine, curCode.toString() });
        switch (curCode) {
            .ConstantOp, .DefineGlobalOp, .GetGlobalOp, .SetGlobalOp => {
                const constant_idx = self.codeSlice[ip + 1];
                const constant = self.constantSlice[constant_idx];
                try writer.print("[addr: {d:>3} -> {f}]\n", .{ constant_idx, constant });
                return 2;
            },
            .DefineLocalOp, .GetLocalOp, .SetLocalOp => {
                const slot = self.codeSlice[ip + 1];
                try writer.print("[slot: {d:>3}]\n", .{slot});
                return 2;
            },
            .JumpIfFalseOp, .JumpOp => {
                const upperU8 = @as(u16, self.codeSlice[ip + 1]);
                const lowerU8 = @as(u16, self.codeSlice[ip + 2]);
                const offset = upperU8 << 8 | lowerU8;
                try writer.print("[offset: {d:>3}]\n", .{offset});
                return 3;
            },
            .ReturnOp, .NegateOp, .AddOp, .SubOp, .MultOp, .DivOp, .PrintOp, .PopOp, .NilOp => {
                try writer.print("\n", .{});
                return 1;
            },
        }
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

    pub fn writeCodeAndRemeber(self: *ByteCodeInfo, alloc: Allocator, code: u8, line: usize) Allocator.Error!usize {
        try self.byteCodeList.append(alloc, code);
        try self.lineList.append(alloc, line);
        return self.byteCodeList.len - 1;
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
            .ConstantOp, .DefineGlobalOp, .GetGlobalOp, .SetGlobalOp => {
                const constant_idx = self.byteCodeList.items[ip + 1];
                const constant = self.constantList.items[constant_idx];
                try writer.print("{s} {d:>3} '{f}'\n", .{ curCode.toString(), constant_idx, constant });
                return 2;
            },
            .DefineLocalOp, .GetLocalOp, .SetLocalOp => {
                const slot = self.byteCodeList.items[ip + 1];
                try writer.print("{s} {d:>3}\n", .{ curCode.toString(), slot });
                return 2;
            },
            .ReturnOp, .NegateOp, .AddOp, .SubOp, .MultOp, .DivOp, .PrintOp, .PopOp, .NilOp => {
                try writer.print("{s}\n", .{curCode.toString()});
                return 1;
            },
        }
    }
};
