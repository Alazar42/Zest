const zest = @import("zest");

pub const Product = struct {
    id: u32,
    name: []const u8,
    price: f64,

    // Universal Comptime ORM Mixin (SQLite, PostgreSQL, MongoDB)
    pub const model = zest.Model(@This());

    // Automated FastAPI-grade Schema Validation
    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 3);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};
