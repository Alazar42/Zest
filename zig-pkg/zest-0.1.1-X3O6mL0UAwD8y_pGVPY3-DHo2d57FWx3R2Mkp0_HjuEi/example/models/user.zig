const zest = @import("zest");

id: u32,
username: []const u8,
role: []const u8 = "user",

pub const model = zest.Model(@This());
