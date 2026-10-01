const std = @import("std");
const zest = @import("zest");

const jwt_secret = "zest_production_secret_key_12345";

/// POST /auth/login: Issues a signed JWT and sets an HttpOnly cookie.
pub fn login(req: *zest.Request, res: *zest.Response) !void {
    const token = try zest.jwt.sign(req.allocator, "{\"sub\":\"user123\",\"role\":\"developer\"}", jwt_secret);
    defer req.allocator.free(token);

    try res.setCookie(.{
        .name = "access_token",
        .value = token,
        .http_only = true,
        .same_site = .lax,
    });

    try res.jsonValue(.{
        .token = token,
        .message = "Logged in successfully",
    });
}

/// GET /auth/profile: Protected route that verifies Bearer token or HttpOnly Cookie.
pub fn getProfile(req: *zest.Request, res: *zest.Response) !void {
    const token = req.bearerToken() orelse req.cookie("access_token") orelse {
        try res.status(.unauthorized, "{\"error\": \"Missing authentication token\"}");
        return;
    };

    const payload = zest.jwt.verify(req.allocator, token, jwt_secret) catch {
        try res.status(.unauthorized, "{\"error\": \"Invalid or expired token\"}");
        return;
    };
    defer req.allocator.free(payload);

    try res.json(payload);
}
