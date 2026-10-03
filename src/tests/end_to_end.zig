const main = @import("../main.zig");
const std = @import("std");
const vm = @import("../vm.zig");

fn checkEndToEndSucceed(src: []const u8, expect: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{ .stressGC = true }, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try main.interpret(allocator, src, &machine, &output.writer);

    const actual = output.writer.buffered();
    std.testing.expectEqualStrings(expect, actual) catch |err| {
        std.debug.print("    expect output:\n{s}", .{expect});
        std.debug.print("    actual output:\n{s}", .{actual});
        return err;
    };
    // Check clean execution
    std.testing.expectEqual(@as(usize, 0), machine.frameCount) catch |err| {
        std.debug.print("    Dirty cleanup: FrameCount not 0", .{});
        return err;
    };
    std.testing.expectEqual(@as(usize, 0), machine.stack.length) catch |err| {
        std.debug.print("    Dirty cleanup: Stack length not 0", .{});
        return err;
    };
}

fn checkEndToEndRuntimeErr(source: []const u8) !void {
    const allocator = std.testing.allocator;
    var machine = try vm.VM.initSettings(.{}, allocator);
    defer machine.deinit(allocator);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    std.testing.expectError(
        error.RuntimeError,
        main.interpret(allocator, source, &machine, &output.writer),
    ) catch |err| {
        std.debug.print("    Given source:\n{s}", .{source});
        return err;
    };
}

test "ETE: basic arithmetic" {
    try checkEndToEndSucceed("print 1 + 2 * 3;", "7\n");
}

test "ETE: variable shadowing" {
    try checkEndToEndSucceed(
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

test "ETE: local variable changed in multiple scope" {
    try checkEndToEndSucceed(
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

test "ETE: basic for-loop" {
    try checkEndToEndSucceed(
        \\for (var i = 0; i < 4; i = i + 1) print i;
    ,
        "0\n1\n2\n3\n",
    );
}

test "ETE: returning functions" {
    try checkEndToEndSucceed(
        \\fun add(a, b) {
        \\    return a + b;
        \\}
        \\print add(20, 22);
    ,
        "42\n",
    );
}

test "ETE: string interning & string concat" {
    try checkEndToEndSucceed(
        \\var left = "hel";
        \\var right = "lo";
        \\print left + right;
        \\print (left + right) == "hello";
    , "hello\ntrue\n");
}

test "ETE: comparison, equality, and boolean negation" {
    try checkEndToEndSucceed(
        \\print 1 < 2;
        \\print 2 <= 2;
        \\print 3 > 4;
        \\print 4 >= 4;
        \\print "same" == "same";
        \\print nil == nil;
        \\print true != false;
        \\print !false;
    , "true\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\n");
}

test "ETE: if, else, and nearest dangling else" {
    try checkEndToEndSucceed(
        \\if (true) print "then"; else print "unreached";
        \\if (false) print "unreached"; else print "else";
        \\if (true) if (false) print "unreached"; else print "inner else";
    , "then\nelse\ninner else\n");
}

test "ETE: while-loop mutates its condition variable" {
    try checkEndToEndSucceed(
        \\var i = 0;
        \\while (i < 3) {
        \\    print i;
        \\    i = i + 1;
        \\}
    , "0\n1\n2\n");
}

test "ETE: chained assignment preserves the assigned value" {
    try checkEndToEndSucceed(
        \\var a = "before a";
        \\var b = "before b";
        \\print a = b = "after";
        \\print a;
        \\print b;
    , "after\nafter\nafter\n");
}

test "ETE: falling off a function returns nil" {
    try checkEndToEndSucceed(
        \\fun noReturn() {
        \\    "ignored";
        \\}
        \\print noReturn();
    , "<nil>\n");
}

test "ETE: recursive function calls" {
    try checkEndToEndSucceed(
        \\fun factorial(n) {
        \\    if (n <= 1) return 1;
        \\    return n * factorial(n - 1);
        \\}
        \\print factorial(6);
    , "720\n");
}

test "ETE: closure keeps a block local alive" {
    try checkEndToEndSucceed(
        \\var closure;
        \\{
        \\    var local = "captured";
        \\    fun capture() {
        \\        print local;
        \\    }
        \\    closure = capture;
        \\}
        \\closure();
    , "captured\n");
}

test "ETE: closure captures a function parameter" {
    try checkEndToEndSucceed(
        \\fun makePrinter(value) {
        \\    fun printValue() {
        \\        print value;
        \\    }
        \\    return printValue;
        \\}
        \\var printAnswer = makePrinter("answer");
        \\printAnswer();
    , "answer\n");
}

test "ETE: closure mutates captured state across calls" {
    try checkEndToEndSucceed(
        \\fun makeCounter(start) {
        \\    var count = start;
        \\    fun next() {
        \\        count = count + 1;
        \\        return count;
        \\    }
        \\    return next;
        \\}
        \\var counter = makeCounter(40);
        \\print counter();
        \\print counter();
    , "41\n42\n");
}

test "ETE: sibling closures share one captured variable" {
    try checkEndToEndSucceed(
        \\var getValue;
        \\var setValue;
        \\fun installClosures() {
        \\    var value = "before";
        \\    fun get() {
        \\        print value;
        \\    }
        \\    fun set() {
        \\        value = "after";
        \\    }
        \\    getValue = get;
        \\    setValue = set;
        \\}
        \\installClosures();
        \\getValue();
        \\setValue();
        \\getValue();
    , "before\nafter\n");
}

test "ETE: separate closure instances keep separate state" {
    try checkEndToEndSucceed(
        \\fun makeCounter() {
        \\    var count = 0;
        \\    fun next() {
        \\        count = count + 1;
        \\        return count;
        \\    }
        \\    return next;
        \\}
        \\var first = makeCounter();
        \\var second = makeCounter();
        \\print first();
        \\print first();
        \\print second();
    , "1\n2\n1\n");
}

test "ETE: nested closure captures through multiple functions" {
    try checkEndToEndSucceed(
        \\fun outer() {
        \\    var a = "a";
        \\    fun middle() {
        \\        var b = "b";
        \\        fun inner() {
        \\            print a;
        \\            print b;
        \\        }
        \\        return inner;
        \\    }
        \\    return middle();
        \\}
        \\var closure = outer();
        \\closure();
    , "a\nb\n");
}

test "ETE: arithmetic precedence and left associativity" {
    try checkEndToEndSucceed(
        \\print 1 + 2 * 3 == 7;
        \\print (1 + 2) * 3 == 9;
        \\print 8 / 4 / 2 == 1;
        \\print 5 - 2 - 1 == 2;
        \\print -1 + 2 == 1;
    , "true\ntrue\ntrue\ntrue\ntrue\n");
}

test "ETE: uninitialized variables contain nil and remain assignable" {
    try checkEndToEndSucceed(
        \\var global;
        \\print global;
        \\global = "global";
        \\print global;
        \\{
        \\    var local;
        \\    print local;
        \\    local = "local";
        \\    print local;
        \\}
    , "<nil>\nglobal\n<nil>\nlocal\n");
}

test "ETE: closure binds before a later local declaration" {
    try checkEndToEndSucceed(
        \\var value = "global";
        \\{
        \\    fun showValue() {
        \\        print value;
        \\    }
        \\    showValue();
        \\    var value = "block";
        \\    showValue();
        \\}
    , "global\nglobal\n");
}

test "ETE: functions are first-class values" {
    try checkEndToEndSucceed(
        \\fun addOne(value) {
        \\    return value + 1;
        \\}
        \\fun apply(functionValue, value) {
        \\    return functionValue(value);
        \\}
        \\var operation = addOne;
        \\print operation(40);
        \\print apply(operation, 41);
    , "41\n42\n");
}

test "ETE: call arguments evaluate from left to right" {
    try checkEndToEndSucceed(
        \\fun echo(value) {
        \\    print value;
        \\    return value;
        \\}
        \\fun last(a, b, c) {
        \\    return c;
        \\}
        \\print last(echo("a"), echo("b"), echo("c"));
    , "a\nb\nc\nc\n");
}

test "ETE: local function recurses through its captured binding" {
    try checkEndToEndSucceed(
        \\{
        \\    fun countDown(n) {
        \\        print n;
        \\        if (n > 1) countDown(n - 1);
        \\    }
        \\    countDown(3);
        \\}
    , "3\n2\n1\n");
}

test "ETE: return exits nested control flow" {
    try checkEndToEndSucceed(
        \\fun findThree() {
        \\    var i = 0;
        \\    while (i < 5) {
        \\        if (i == 3) return i;
        \\        i = i + 1;
        \\    }
        \\    return -1;
        \\}
        \\print findThree();
    , "3\n");
}

test "ETE: for-loop supports omitted initializer and increment" {
    try checkEndToEndSucceed(
        \\var i = 0;
        \\for (; i < 2; i = i + 1) print i;
        \\for (var j = 2; j < 4;) {
        \\    print j;
        \\    j = j + 1;
        \\}
    , "0\n1\n2\n3\n");
}

test "ETE: loop locals do not replace an outer binding" {
    try checkEndToEndSucceed(
        \\var i = "outside";
        \\for (var i = 0; i < 2; i = i + 1) print i;
        \\print i;
        \\while (false) print "unreached";
    , "0\n1\noutside\n");
}

test "ETE: closing a scope preserves multiple captured locals" {
    try checkEndToEndSucceed(
        \\var showA;
        \\var showB;
        \\{
        \\    var a = "a";
        \\    var b = "b";
        \\    fun captureA() {
        \\        print a;
        \\    }
        \\    fun captureB() {
        \\        print b;
        \\    }
        \\    showA = captureA;
        \\    showB = captureB;
        \\}
        \\showB();
        \\showA();
    , "b\na\n");
}

test "ETE: closed upvalue survives reuse of its stack slot" {
    try checkEndToEndSucceed(
        \\var saved;
        \\{
        \\    var value = "closed";
        \\    fun capture() {
        \\        print value;
        \\    }
        \\    saved = capture;
        \\}
        \\{
        \\    var value = "replacement";
        \\    print value;
        \\}
        \\saved();
    , "replacement\nclosed\n");
}

test "ETE: deeply nested closure mutates an outer variable" {
    try checkEndToEndSucceed(
        \\fun outer() {
        \\    var value = 40;
        \\    fun middle() {
        \\        fun inner() {
        \\            value = value + 1;
        \\            return value;
        \\        }
        \\        return inner;
        \\    }
        \\    return middle();
        \\}
        \\var increment = outer();
        \\print increment();
        \\print increment();
    , "41\n42\n");
}

test "ETE: closure captures the nearest shadowed binding" {
    try checkEndToEndSucceed(
        \\fun outer() {
        \\    var value = "outer";
        \\    fun middle() {
        \\        var value = "middle";
        \\        fun inner() {
        \\            print value;
        \\        }
        \\        return inner;
        \\    }
        \\    return middle();
        \\}
        \\var show = outer();
        \\show();
    , "middle\n");
}

test "ETE: function equality uses closure identity" {
    try checkEndToEndSucceed(
        \\fun first() {}
        \\var alias = first;
        \\fun second() {}
        \\print first == alias;
        \\print first == second;
    , "true\nfalse\n");
}

test "ETE: chained string concatenation" {
    try checkEndToEndSucceed(
        \\print "a" + "b" + "c";
        \\print "a" + ("b" + "c") == "abc";
    , "abc\ntrue\n");
}

test "ETE: empty scripts and blocks have no output" {
    try checkEndToEndSucceed("", "");
    try checkEndToEndSucceed("{}", "");
}

test "ETE: decimal number literals retain their value" {
    try checkEndToEndSucceed(
        \\print 123.456;
        \\print 0.001;
        \\print 1.0;
    , "123.456\n0.001\n1\n");
}

test "ETE: equality across different value types" {
    try checkEndToEndSucceed(
        \\print 0 == false;
        \\print nil == false;
        \\print "1" == 1;
        \\print "1" != 1;
    , "false\nfalse\nfalse\ntrue\n");
}

test "ETE: nested unary operators" {
    try checkEndToEndSucceed(
        \\print -(-3);
        \\print !!true;
        \\print !!!false;
    , "3\ntrue\ntrue\n");
}

test "ETE: mutually recursive global functions" {
    try checkEndToEndSucceed(
        \\fun isEven(n) {
        \\    if (n == 0) return true;
        \\    return isOdd(n - 1);
        \\}
        \\fun isOdd(n) {
        \\    if (n == 0) return false;
        \\    return isEven(n - 1);
        \\}
        \\print isEven(10);
        \\print isOdd(10);
    , "true\nfalse\n");
}

test "ETE: explicit return without a value returns nil" {
    try checkEndToEndSucceed(
        \\fun stop() {
        \\    return;
        \\    print "unreached";
        \\}
        \\print stop();
    , "<nil>\n");
}

test "ETE: assigning a parameter does not change its argument" {
    try checkEndToEndSucceed(
        \\var argument = "outside";
        \\fun change(argument) {
        \\    argument = "inside";
        \\    print argument;
        \\}
        \\change(argument);
        \\print argument;
    , "inside\noutside\n");
}

test "ETE: parameters preserve argument order" {
    try checkEndToEndSucceed(
        \\fun printEight(a, b, c, d, e, f, g, h) {
        \\    print a;
        \\    print b;
        \\    print c;
        \\    print d;
        \\    print e;
        \\    print f;
        \\    print g;
        \\    print h;
        \\}
        \\printEight(1, 2, 3, 4, 5, 6, 7, 8);
    , "1\n2\n3\n4\n5\n6\n7\n8\n");
}

test "ETE: closure observes assignment before its scope closes" {
    try checkEndToEndSucceed(
        \\fun makeClosure() {
        \\    var value = "before";
        \\    fun show() {
        \\        print value;
        \\    }
        \\    value = "after";
        \\    return show;
        \\}
        \\var show = makeClosure();
        \\show();
    , "after\n");
}

test "ETE: closure created in a loop sees the final loop value" {
    try checkEndToEndSucceed(
        \\var saved;
        \\for (var i = 0; i < 3; i = i + 1) {
        \\    fun capture() {
        \\        print i;
        \\    }
        \\    saved = capture;
        \\}
        \\saved();
    , "3\n");
}

test "ETE: explicit return closes every captured local" {
    try checkEndToEndSucceed(
        \\var showA;
        \\var showB;
        \\fun install() {
        \\    var a = "a";
        \\    var b = "b";
        \\    fun captureA() {
        \\        print a;
        \\    }
        \\    fun captureB() {
        \\        print b;
        \\    }
        \\    showA = captureA;
        \\    showB = captureB;
        \\    return "installed";
        \\}
        \\print install();
        \\showA();
        \\showB();
    , "installed\na\nb\n");
}

test "ETE: separately created functions have distinct closure identity" {
    try checkEndToEndSucceed(
        \\fun makeFunction() {
        \\    fun result() {}
        \\    return result;
        \\}
        \\var first = makeFunction();
        \\var second = makeFunction();
        \\print first == first;
        \\print first == second;
    , "true\nfalse\n");
}

test "ETE: local slots are reusable in separate blocks" {
    try checkEndToEndSucceed(
        \\{
        \\    var value = "first";
        \\    print value;
        \\}
        \\{
        \\    var value = "second";
        \\    print value;
        \\}
    , "first\nsecond\n");
}

test "ETE: identifiers may begin with keywords" {
    try checkEndToEndSucceed(
        \\var falsehood = "falsehood";
        \\var printable = "printable";
        \\var returnValue = "returnValue";
        \\print falsehood;
        \\print printable;
        \\print returnValue;
    , "falsehood\nprintable\nreturnValue\n");
}

test "ETE: nested loops keep independent locals" {
    try checkEndToEndSucceed(
        \\var outer = 0;
        \\while (outer < 2) {
        \\    var inner = 0;
        \\    while (inner < 2) {
        \\        print outer * 10 + inner;
        \\        inner = inner + 1;
        \\    }
        \\    outer = outer + 1;
        \\}
    , "0\n1\n10\n11\n");
}

test "ETE: for-loop accepts an expression initializer" {
    try checkEndToEndSucceed(
        \\var i = 0;
        \\for (i = 1; i < 3; i = i + 1) print i;
        \\print i;
    , "1\n2\n3\n");
}

test "ETE: returned function can be called immediately" {
    try checkEndToEndSucceed(
        \\fun makeAnswer() {
        \\    fun answer() {
        \\        return 42;
        \\    }
        \\    return answer;
        \\}
        \\print makeAnswer()();
    , "42\n");
}

test "ETE: compiler roots survive nested function compilation" {
    try checkEndToEndSucceed(
        \\fun makeJournal(title) {
        \\    var text = "=== " + title;
        \\
        \\    fun record(entry) {
        \\        text = text + "\n- ";
        \\        text = text + entry;
        \\        return text;
        \\    }
        \\
        \\    return record;
        \\}
        \\
        \\fun makeWorker(prefix) {
        \\    fun process(payload) {
        \\        var message = prefix + payload;
        \\        return message + "!";
        \\    }
        \\
        \\    return process;
        \\}
        \\
        \\var journal = makeJournal("batch processing report");
        \\
        \\for (var batch = 0; batch < 20; batch = batch + 1) {
        \\    var worker = makeWorker("worker: ");
        \\    var result = worker("processed batch");
        \\    journal(result);
        \\
        \\    var scratch = "temporary " + "buffer";
        \\    scratch = scratch + " discarded";
        \\}
        \\
        \\print journal("all batches complete");
    ,
        "=== batch processing report" ++
            ("\\n- worker: processed batch!" ** 20) ++
            "\\n- all batches complete\n",
    );
}

test "ETE runtime error: reading an undefined global" {
    try checkEndToEndRuntimeErr("print missing;");
}

test "ETE runtime error: assigning an undefined global" {
    try checkEndToEndRuntimeErr("missing = 42;");
}

test "ETE runtime error: calling a non-function value" {
    try checkEndToEndRuntimeErr(
        \\var value = "not callable";
        \\value();
    );
}

test "ETE runtime error: condition must be boolean" {
    try checkEndToEndRuntimeErr("if (1) print 1;");
}

test "ETE runtime error: numeric negation rejects strings" {
    try checkEndToEndRuntimeErr("print -\"value\";");
}

test "ETE runtime error: logical negation requires a boolean" {
    try checkEndToEndRuntimeErr("print !nil;");
}

test "ETE runtime error: addition rejects mixed operand types" {
    try checkEndToEndRuntimeErr("print 1 + \"2\";");
}

test "ETE runtime error: ordering rejects strings" {
    try checkEndToEndRuntimeErr("print \"a\" < \"b\";");
}
