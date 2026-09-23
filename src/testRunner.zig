const builtin = @import("builtin");
const std = @import("std");

pub fn main(init: std.process.Init.Minimal) void {
    const tests = builtin.test_functions;
    var passed: usize = 0;
    var failed: usize = 0;
    var leaked: usize = 0;

    std.debug.print("\n=== zlox test suite: {d} tests ===\n", .{tests.len});

    for (tests, 0..) |testFn, index| {
        std.debug.print("\n[{d}/{d}] {s}\n", .{ index + 1, tests.len, testFn.name });

        std.testing.allocator_instance = .{};
        std.testing.io_instance = .init(std.testing.allocator, .{
            .argv0 = .init(init.args),
            .environ = init.environ,
        });
        std.testing.environ = init.environ;

        const result = testFn.func();

        std.testing.io_instance.deinit();
        const leakCount = std.testing.allocator_instance.detectLeaks();
        std.testing.allocator_instance.deinitWithoutLeakChecks();

        if (result) |_| {
            if (leakCount == 0) {
                passed += 1;
                std.debug.print("    PASS\n", .{});
            } else {
                leaked += 1;
                std.debug.print("    FAIL: leaked {d} allocation(s)\n", .{leakCount});
            }
        } else |err| {
            failed += 1;
            std.debug.print("    FAIL: {t}\n", .{err});
            if (leakCount != 0) {
                leaked += 1;
                std.debug.print("    additionally leaked {d} allocation(s)\n", .{leakCount});
            }
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpErrorReturnTrace(trace);
            }
        }
    }

    std.debug.print(
        "\n=== result: {d} passed, {d} failed, {d} leaked ===\n\n",
        .{ passed, failed, leaked },
    );

    if (failed != 0 or leaked != 0) {
        std.process.exit(1);
    }
}
