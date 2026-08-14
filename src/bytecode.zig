pub const bytecode = union(enum) {
    operation: opCode,
    content: u8,

    pub fn isOperation(self: bytecode) bool {
        return switch (self) {
            .operation => true,
            .content => false,
        };
    }
};

pub const opCode = enum(u8) {
    ReturnOp,

    pub fn toString(self: opCode) []const u8 {
        switch (self) {
            .ReturnOp => "return",
        }
    }
};
