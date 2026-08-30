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
    GetGlobalOp,
    SetGlobalOp,
    DefineLocalOp,
    GetLocalOp,
    SetLocalOp,

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
            .NilOp => "nilOp",
            .DefineGlobalOp => "defGlobal",
            .GetGlobalOp => "getGlobal",
            .SetGlobalOp => "setGlobal",
            .DefineLocalOp => "defLocal",
            .GetLocalOp => "getLocal",
            .SetLocalOp => "setLocal",
        };
    }
};
