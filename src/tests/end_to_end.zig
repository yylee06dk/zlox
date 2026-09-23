const support = @import("support.zig");

test "end-to-end boundary: arithmetic precedence" {
    try support.checkOutput("print 1 + 2 * 3;", "7\n");
}

test "end-to-end boundary: locals shadow and restore outer bindings" {
    try support.checkOutput(
        \\{
        \\    var message = "outside";
        \\    {
        \\        var message = "inside";
        \\        print message;
        \\    }
        \\    print message;
        \\}
    , "inside\noutside\n");
}

test "end-to-end regression: assignment in an inner scope updates the resolved outer local" {
    try support.checkOutput(
        \\{
        \\    var message = "Hello";
        \\    {
        \\        print message;
        \\        message = "World";
        \\        print message;
        \\    }
        \\    print message;
        \\}
    , "Hello\nWorld\nWorld\n");
}

test "end-to-end boundary: loops do not accumulate stack values" {
    try support.checkOutput(
        "for (var i = 0; i < 4; i = i + 1) print i;",
        "0\n1\n2\n3\n",
    );
}

test "end-to-end boundary: function declarations, calls, and returns" {
    try support.checkOutput(
        "fun add(a, b) { return a + b; } print add(20, 22);",
        "42\n",
    );
}

test "end-to-end regression: strings format and intern after concatenation" {
    try support.checkOutput(
        \\var left = "hel";
        \\var right = "lo";
        \\print left + right;
        \\print (left + right) == "hello";
    , "hello\ntrue\n");
}

test "end-to-end REPL boundary: globals persist across successful submissions" {
    try support.checkSession(
        &.{
            "var answer = 40;",
            "answer = answer + 2;",
            "print answer;",
        },
        "42\n",
    );
}

test "end-to-end regression: a failed submission releases all owned allocations" {
    try support.checkRuntimeError("print missing;");
}

test "end-to-end REPL boundary: execution recovers after a runtime error" {
    try support.checkRuntimeRecovery(
        "print 1 + true;",
        "print 42;",
        "42\n",
    );
}
