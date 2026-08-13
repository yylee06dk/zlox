pub const bytecode = union(enum) {
    operation: opCode,
    info: u8,

    pub fn isOperation(self: bytecode) bool {
        return switch (self) {
            .operation => true,
            .info => false,
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
