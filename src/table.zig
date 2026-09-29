const std = @import("std");
const Value = @import("values.zig").Value;

const Allocator = std.mem.Allocator;
const baseSize = 8;
const loadFactor = 0.75;
const t = std.debug.print;

pub const Table = struct {
    count: usize,
    capacity: usize,
    baseArray: []?Entry,

    const Entry = struct {
        key: *Value.String,
        value: Value, // 16bytes
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

    pub fn set(self: *Table, key: *Value.String, value: Value, alloc: Allocator) !bool {
        if (@as(f64, @floatFromInt(self.capacity)) * loadFactor < @as(f64, @floatFromInt(self.count + 1))) {
            try self.growCapacity(alloc);
        }

        const entry = Entry{ .key = key, .value = value };
        const idx = self.findEntryPos(key);
        const isNewKey = self.baseArray[idx] == null;

        self.baseArray[idx] = entry;
        if (isNewKey) {
            self.count += 1;
        }
        return isNewKey;
    }

    pub fn get(self: *const Table, key: *Value.String) ?Value {
        const pos = self.findEntryPos(key);
        if (self.baseArray[pos]) |e| {
            return e.value;
        } else {
            return null;
        }
    }

    pub fn contains(self: *const Table, string: []const u8, hash: u32) ?*Value.String {
        var expectPos = @mod(hash, self.capacity);
        //std.debug.print("\n", .{});
        for (0..self.capacity) |_| {
            expectPos = @mod(expectPos + 1, self.capacity);
            //std.debug.print("{d}\n", .{expectPos});
            const entry = self.baseArray[expectPos];
            //std.debug.print("E:{?}\n", .{entry});
            if (entry == null) return null;
            const e = if (entry) |e| e else unreachable;
            if (hash == e.key.hash and e.key.length == string.len) {
                if (std.mem.eql(u8, e.key.getString(), string)) {
                    return e.key;
                }
            }
        }
        unreachable;
    }

    fn findEntryPos(self: *const Table, key: *Value.String) usize {
        var expectPos = @mod(key.hash, self.capacity);

        for (0..self.capacity) |_| {
            expectPos = @mod(expectPos + 1, self.capacity);
            const entry = self.baseArray[expectPos];
            if (entry) |e| {
                if (e.key == key) break;
                continue;
            }
            break;
        }
        return expectPos;
    }

    fn growCapacity(self: *Table, alloc: Allocator) Allocator.Error!void { // In place (in struct's perspective)
        const newCapacity = self.capacity * 2;
        const ptrOld = self.baseArray;
        const ptrNew = try alloc.alloc(?Entry, newCapacity);
        defer alloc.free(ptrOld);
        errdefer alloc.free(ptrNew);
        initSliceWithNull(ptrNew);

        var tempTable: Table = .{
            .capacity = newCapacity,
            .count = self.count,
            .baseArray = ptrNew,
        };

        for (0..self.capacity) |idx| {
            const oldEntry = self.baseArray[idx] orelse continue;
            _ = try tempTable.set(oldEntry.key, oldEntry.value, alloc);
        }

        self.baseArray = ptrNew;
        self.capacity = newCapacity;
    }
};

// Helper functions
fn initSliceWithNull(slice: []?Table.Entry) void {
    for (0..slice.len) |idx| {
        slice[idx] = null;
    }
}
