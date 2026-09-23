// This file is only the test-suite index. Test logic belongs to the boundary
// specific files under src/tests/.
test "load boundary test suites" {
    _ = @import("tests/scanner.zig");
    _ = @import("tests/compiler.zig");
    _ = @import("tests/vm.zig");
    _ = @import("tests/end_to_end.zig");
    _ = @import("tests/table.zig");
}

// Keep implementation-local test blocks reachable from the central test root.
test "load colocated implementation tests" {
    _ = @import("bytecode.zig");
    _ = @import("bytecodeInfo.zig");
    _ = @import("common.zig");
    _ = @import("compiler.zig");
    _ = @import("memory.zig");
    _ = @import("objects.zig");
    _ = @import("objectStore.zig");
    _ = @import("scanner.zig");
    _ = @import("table.zig");
    _ = @import("tokens.zig");
    _ = @import("values.zig");
    _ = @import("vm.zig");
    _ = @import("vmStack.zig");
}
