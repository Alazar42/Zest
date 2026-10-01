const zest = @import("zest");
const auth_ctrl = @import("../controllers/auth.zig");

/// Registers all authentication routes on the provided router or route group.
pub fn register(g: *zest.Group) !void {
    try g.post("/login", auth_ctrl.login);
    try g.get("/profile", auth_ctrl.getProfile);
}
