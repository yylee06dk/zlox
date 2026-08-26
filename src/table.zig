const std = @import("std");
const values = @import("values.zig");
const objects = @import("objects.zig");
const strings = @import("strings.zig");

const Allocator = std.mem.Allocator;
const baseSize = 8;
const loadFactor = 0.75;
const t = std.debug.print;

pub const Table = struct {
    count: usize,
    capacity: usize,
    baseArray: []?Entry,

    const Entry = struct {
        key: *strings.ObjectString,
        value: values.Value, // 16bytes
    };

    pub fn init(alloc: Allocator) !Table {
        const slice = try alloc.alloc(?Entry, baseSize);
        initSliceWithNull(slice);
        return .{
            .count = 0,
            .capacity = baseSize,
            .baseArray = slice,
        };
    }

    pub fn deinit(self: *Table, alloc: Allocator) void {
        alloc.free(self.baseArray);
    }

    pub fn set(self: *Table, key: *strings.ObjectString, value: values.Value, alloc: Allocator) !bool {
        if (@as(f64, @floatFromInt(self.capacity)) * loadFactor < @as(f64, @floatFromInt(self.count + 1))) {
            try self.growCapacity(alloc);
        }

        const entry = Entry{ .key = key, .value = value };
        const idx = self.findEntryPos(key);
        const isNewKey = self.baseArray[idx] == null;

        self.baseArray[idx] = entry;
        return isNewKey;
    }

    pub fn contains(self: *const Table, string: []const u8, hash: u32) ?*strings.ObjectString {
        var expectPos = @mod(hash, self.capacity);
        while (true) : (expectPos = @mod(expectPos + 1, self.capacity)) {
            t("from contains\n", .{});
            const e = if (self.baseArray[expectPos]) |e| e else return null;
            t("from contains0: {s}|{s}\n", .{ e.key.getString(), string });
            if (hash == e.key.hash and e.key.length == string.len) {
                t("from contains1: {s}|{s}\n", .{ e.key.getString(), string });
                if (std.mem.eql(u8, e.key.getString(), string)) {
                    t("from contains2: {s}|{s}\n", .{ e.key.getString(), string });
                    return e.key;
                }
            }
        }
        return null;
    }

    fn findEntryPos(self: *const Table, key: *strings.ObjectString) usize {
        var expectPos = @mod(key.hash, self.capacity);

        while (true) : (expectPos = @mod(expectPos + 1, self.capacity)) {
            const entry = self.baseArray[expectPos];
            if (entry) |e| {
                if (e.key != key) continue; //Available via string interning!
            }
            break;
        }
        return expectPos;
    }

    fn growCapacity(self: *Table, alloc: Allocator) !void { // In place (in struct's perspective)
        const newCapacity = self.capacity * 2;
        const ptrNew = try alloc.realloc(self.baseArray, newCapacity);
        self.capacity = newCapacity;

        const tempTable = Table{
            .count = self.count,
            .capacity = newCapacity,
            .baseArray = ptrNew,
        };

        initSliceWithNull(ptrNew);
        for (self.baseArray) |entry| {
            if (entry) |e| {
                const idx = tempTable.findEntryPos(e.key);
                ptrNew[idx] = e;
            }
        }

        self.baseArray = ptrNew;
    }
};

fn initSliceWithNull(slice: []?Table.Entry) void {
    for (0..slice.len) |idx| {
        slice[idx] = null;
    }
}
