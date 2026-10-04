A zig built bytecode interpreter of lox from the book [Crafting Interpreters](https://craftinginterpreters.com/) by Bob Nystrom.

#### How to build
- Step 1. Download zig 0.16.0 (https://codeberg.org/ziglang/zig)
- Step 2. Run zig build and you'll get a binary at ./zig-out/bin/ called `zlox`
(Also, you got options like `zig build run` that runs the REPL, `zig build run-debug` which runs the REPL in debug mode(shows bytecode, vm execute trace, gc log)

#### Usage of binary
`zlox` will shoot up a REPL.
`zlox {file}` will run the file as input lox code.
##### Flags
`-b` shows bytecode.
`-v` shows vm trace
`-g` shows gc log
`-s` stresses gc by booting up the gc every time an allocation is added.
`-d` is equal to `-bvg`
=> `-ds` flag can be used to fully debug and see what's happening.

#### Usage of A.I.
A.I. (codex, 5.6-sol was mainly used) was used mainly to write build.zig files and set up the testing environment (in VScode with lldb extension) and with a provided interface for testing (check~~~ functions), it translated some tests provided in the repository of the book 
or it created some by itself.

#### Difference from the original language
- No multi-line strings
