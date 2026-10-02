const std = @import("std");
const Request = @import("request.zig");
const Response = @import("response.zig");

pub const MiddlewareFn = *const fn (req: *Request, res: *Response) anyerror!bool;

pub const CorsOptions = struct {
    origin: []const u8 = "*",
    methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS",
    headers: []const u8 = "content-type, authorization, accept",
    allowCredentials: bool = false,
    exposeHeaders: []const u8 = "*",
};

/// Formats the HTTP method with distinct ANSI colors:
/// - GET: Bold Green
/// - POST: Bold Blue
/// - PUT: Bold Yellow
/// - DELETE: Bold Red
/// - PATCH: Bold Magenta
/// - HEAD: Bold Cyan
/// - OPTIONS: Dim Gray
pub fn formatMethod(method: std.http.Method) []const u8 {
    return switch (method) {
        .GET => "\x1b[1;32mGET   \x1b[0m",
        .POST => "\x1b[1;34mPOST  \x1b[0m",
        .PUT => "\x1b[1;33mPUT   \x1b[0m",
        .DELETE => "\x1b[1;31mDELETE\x1b[0m",
        .PATCH => "\x1b[1;35mPATCH \x1b[0m",
        .HEAD => "\x1b[1;36mHEAD  \x1b[0m",
        .OPTIONS => "\x1b[1;90mOPTION\x1b[0m",
        else => @tagName(method),
    };
}

/// Formats the HTTP response status code with distinct ANSI colors:
/// - 2xx: Bold Green (e.g. 200 OK)
/// - 3xx: Bold Cyan (e.g. 302 Found)
/// - 4xx: Bold Yellow (e.g. 404 Not Found)
/// - 5xx: Bold Red (e.g. 500 Internal Server Error)
pub fn formatStatus(buf: *[64]u8, status: std.http.Status) []const u8 {
    const code = @intFromEnum(status);
    const phrase = status.phrase() orelse @tagName(status);

    const color = if (code >= 200 and code < 300)
        "\x1b[1;32m" // Bold Green
    else if (code >= 300 and code < 400)
        "\x1b[1;36m" // Bold Cyan
    else if (code >= 400 and code < 500)
        "\x1b[1;33m" // Bold Yellow
    else
        "\x1b[1;31m"; // Bold Red

    return std.fmt.bufPrint(buf, "{s}{d} {s}\x1b[0m", .{ color, code, phrase }) catch "Unknown";
}

/// Formats the elapsed nanoseconds into a readable string (e.g. "450µs" or "1.24ms").
pub fn formatDuration(nanos: i128, buf: *[32]u8) []const u8 {
    if (nanos < 0) {
        return "0µs";
    }
    if (nanos < 1_000_000) {
        const us = @as(f64, @floatFromInt(nanos)) / 1000.0;
        return std.fmt.bufPrint(buf, "{d:.1}µs", .{us}) catch "0µs";
    }
    const ms = @as(f64, @floatFromInt(nanos)) / 1_000_000.0;
    return std.fmt.bufPrint(buf, "{d:.2}ms", .{ms}) catch "0ms";
}

/// Emits a structured, colored log line for a completed HTTP request.
pub fn logResponse(req: *Request, res: *Response) void {
    const method_colored = formatMethod(req.method());
    var status_buf: [64]u8 = undefined;
    const status_colored = formatStatus(&status_buf, res.status_code);
    var dur_buf: [32]u8 = undefined;
    const dur_str = formatDuration(req.elapsedNanos(), &dur_buf);

    std.log.info("[Zest] {s} {s} {s} \x1b[90m{s}\x1b[0m", .{
        method_colored,
        req.path(),
        status_colored,
        dur_str,
    });
}

/// Middleware that enables structured, colored HTTP request/response logging.
pub fn logger(req: *Request, res: *Response) anyerror!bool {
    _ = req;
    res.log_enabled = true;
    return true;
}

/// Creates a CORS middleware with custom or default options.
/// Automatically handles OPTIONS preflight requests by replying with 204 No Content.
pub fn cors(comptime options: CorsOptions) MiddlewareFn {
    return struct {
        fn handle(req: *Request, res: *Response) anyerror!bool {
            // Determine the appropriate origin header value.
            var origin_val: []const u8 = options.origin;
            if (std.mem.eql(u8, options.origin, "*")) {
                // If wildcard, echo back the request's Origin header if present.
                if (req.getHeader("origin")) |hdr| {
                    origin_val = hdr;
                }
            }
            // Always add CORS headers
            try res.setHeader("access-control-allow-origin", origin_val);
            try res.setHeader("access-control-allow-methods", options.methods);
            try res.setHeader("access-control-allow-headers", options.headers);
            try res.setHeader("access-control-expose-headers", options.exposeHeaders);
            if (options.allowCredentials) {
                try res.setHeader("access-control-allow-credentials", "true");
            }
            // Handle preflight OPTIONS request
            if (req.method() == .OPTIONS) {
                // Include max age for caching preflight response
                try res.setHeader("access-control-max-age", "86400");
                try res.send("", .{ .status = .no_content });
                return false; // Preflight handled
            }
            return true;
        }
    }.handle;
}

const jwt = @import("jwt.zig");

/// JWT authentication guard middleware that verifies `Authorization: Bearer <token>`,
/// extracts the claims payload, injects `auth_user` into `req`, and rejects unauthorized requests with 401.
pub fn jwtAuth(comptime secret: []const u8) MiddlewareFn {
    return struct {
        fn handle(req: *Request, res: *Response) anyerror!bool {
            const token = req.bearerToken() orelse {
                try res.status(.unauthorized, .{
                    .@"error" = "Unauthorized",
                    .detail = "Missing Bearer authorization token",
                });
                return false;
            };

            const payload = jwt.verify(req.allocator, token, secret) catch {
                try res.status(.unauthorized, .{
                    .@"error" = "Unauthorized",
                    .detail = "Invalid or expired JWT token",
                });
                return false;
            };
            req.auth_claims = payload;

            // Extract "sub" if present in payload
            if (std.mem.indexOf(u8, payload, "\"sub\":\"")) |sub_idx| {
                const start = sub_idx + 7;
                if (std.mem.indexOfScalar(u8, payload[start..], '"')) |end_rel| {
                    req.auth_user = payload[start .. start + end_rel];
                }
            } else if (std.mem.indexOf(u8, payload, "\"sub\": \"")) |sub_idx| {
                const start = sub_idx + 8;
                if (std.mem.indexOfScalar(u8, payload[start..], '"')) |end_rel| {
                    req.auth_user = payload[start .. start + end_rel];
                }
            }

            return true;
        }
    }.handle;
}
