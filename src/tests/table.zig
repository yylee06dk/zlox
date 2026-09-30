const std = @import("std");

const objects = @import("../objects.zig");
const objectStore = @import("../objectStore.zig");
const table = @import("../table.zig");
const vm = @import("../vm.zig");

fn intern(machine: *vm.VM, bytes: []const u8, allocator: std.mem.Allocator) !*objects.Object.String {
    return objectStore.makeString(
        bytes,
        bytes.len,
        &machine.gcAlloc,
        &machine.stringPool,
        allocator,
    );
}

test "table boundary: initialization creates only empty slots" {
    var target = try table.Table.init(std.testing.allocator);
    defer target.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), target.count);
    for (target.baseArray) |entry| {
        try std.testing.expect(entry == null);
    }
}

test "table boundary: set and get preserve a value" {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    const key = try intern(&machine, "answer", allocator);
    try std.testing.expect(try machine.globals.set(key, .{ .Number = 42 }, allocator));
    const actual = machine.globals.get(key) orelse return error.MissingValue;
    try std.testing.expectEqual(@as(f64, 42), actual.Number);
}

test "table regression: replacing a key changes its value without changing count" {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    const key = try intern(&machine, "same", allocator);
    try std.testing.expect(try machine.globals.set(key, .{ .Number = 1 }, allocator));
    try std.testing.expect(!try machine.globals.set(key, .{ .Number = 2 }, allocator));

    try std.testing.expectEqual(@as(usize, 1), machine.globals.count);
    const actual = machine.globals.get(key) orelse return error.MissingValue;
    try std.testing.expectEqual(@as(f64, 2), actual.Number);
}

test "table regression: growth preserves every entry and does not retain a freed array" {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    const names = [_][]const u8{
        "key00", "key01", "key02", "key03", "key04",
        "key05", "key06", "key07", "key08", "key09",
        "key10", "key11", "key12", "key13", "key14",
        "key15", "key16", "key17", "key18", "key19",
    };
    var keys: [names.len]*objects.Object.String = undefined;

    for (names, 0..) |name, index| {
        keys[index] = try intern(&machine, name, allocator);
        _ = try machine.globals.set(keys[index], .{ .Number = @floatFromInt(index) }, allocator);
    }

    try std.testing.expect(machine.globals.capacity >= 32);
    try std.testing.expectEqual(names.len, machine.globals.count);
    for (keys, 0..) |key, index| {
        const actual = machine.globals.get(key) orelse return error.MissingValueAfterGrowth;
        try std.testing.expectEqual(@as(f64, @floatFromInt(index)), actual.Number);
    }
}

test "table regression: string interning remains canonical across growth" {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    const names = [_][]const u8{
        "alpha",   "bravo", "charlie", "delta", "echo",
        "foxtrot", "golf",  "hotel",   "india", "juliet",
    };
    const alpha = try intern(&machine, names[0], allocator);
    for (names[1..]) |name| {
        _ = try intern(&machine, name, allocator);
    }

    try std.testing.expect(machine.stringPool.capacity > 8);
    try std.testing.expectEqual(names.len, machine.stringPool.count);
    const alphaAgain = try intern(&machine, "alpha", allocator);
    try std.testing.expectEqual(alpha, alphaAgain);
    try std.testing.expectEqual(names.len, machine.stringPool.count);
}
