pub const opCode = enum(u8) {
    ReturnOp,
    ConstantOp,
    NegateOp,
    AddOp,
    SubOp,
    MultOp,
    DivOp,
    PrintOp,
    PopOp,
    NilOp,
    DefineGlobalOp,

    pub fn toString(self: opCode) []const u8 {
        return switch (self) {
            .ReturnOp => "return",
            .ConstantOp => "constant",
            .NegateOp => "negate",
            .AddOp => "add",
            .SubOp => "sub",
            .MultOp => "mult",
            .DivOp => "div",
            .PrintOp => "print",
            .PopOp => "pop",
        };
    }
};
