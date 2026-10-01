const zest = @import("zest");

id: u32,
name: []const u8,
price: f64,
user_id: u32 = 1,

pub const model = zest.Model(@This());

pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
    zest.validator.requireMinLength(errs, "name", self.name, 2);
    zest.validator.requireMin(errs, "price", self.price, 0.01);
}
