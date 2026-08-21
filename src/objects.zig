pub const ObjectType = enum {
    String,
};

pub const Object = struct {
    kind: ObjectType,
};
