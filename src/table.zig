const std = @import("std");
const values = @import("values.zig");
const objects = @import("objects.zig");
const strings = @import("strings.zig");

const Allocator = std.mem.Allocator;
const baseSize = 8;
const loadFactor = 0.75;

pub const Table = struct {
    count: usize,
    capacity: usize,
    baseArray: []?Entry,

    const Entry = struct {
        key: *strings.ObjectString,
        value: values.Value, // 16bytes
    };

    pub fn init(alloc: Allocator) !Table {
        const slice = try alloc.alloc(Entry, baseSize);
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
        if (@as(f64, self.capacity) * loadFactor < @as(f64, self.count + 1)) {
            self.growCapacity(alloc);
        }

        const entry = Entry{ .key = key, .value = value };
        const idx = self.findEntryPos(key);
        const isNewKey = self.baseArray[idx] == null;

        self.baseArray[idx] = entry;
        return isNewKey;
    }

    fn findEntryPos(self: *Table, key: *strings.ObjectString) usize {
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

    fn growCapacity(self: *Table, alloc: Allocator) !void {
        const newCapacity = self.capacity * 2;
    }
};

fn initSliceWithNull(slice: []?Table.Entry) void {
    for (0..slice.len) |idx| {
        slice[idx] = null;
    }
}
