pub const opCode = enum(u8) {
    ReturnOp,

    pub fn toString(self: opCode) []const u8 {
        switch (self) {
            .ReturnOp => return "return",
        }
    }
};
