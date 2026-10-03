const std = @import("std");
const Request = @import("request.zig");
const Response = @import("response.zig");

pub const MiddlewareFn = *const fn (req: *Request, res: *Response) anyerror!bool;

pub const CorsOptions = struct {
    /// Single allowed origin or pattern (e.g. "*", "https://example.com", "http://localhost:*"). Default: "*".
    origin: []const u8 = "*",

    /// List of allowed origins or wildcard patterns (e.g. &.{ "http://localhost:3000", "http://localhost:5173", "https://*.example.com" }).
    /// If non-empty, incoming request origins are matched against this whitelist.
    origins: []const []const u8 = &.{},

    /// Optional custom function for programmatic dynamic origin validation.
    allowOriginFn: ?*const fn (origin: []const u8) bool = null,

    /// Allowed HTTP methods for CORS requests.
    /// Default: "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS".
    methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS",

    /// Allowed HTTP request headers.
    /// Default: "*" (automatically echoes requested headers during preflight).
    /// Can also be a comma-separated list like "Content-Type, Authorization, X-Requested-With".
    headers: []const u8 = "*",

    /// Headers that browsers are permitted to access from the response.
    /// Default: "*" (all response headers exposed) or custom list like "Content-Length, Content-Disposition, X-Total-Count".
    exposeHeaders: []const u8 = "*",

    /// Indicates whether the request can be made with credentials (cookies, authorization headers, TLS client certs).
    /// Default: false.
    /// In accordance with W3C CORS / Fetch specifications, when credentials are true,
    /// Access-Control-Allow-Origin will NEVER be "*", but rather the matching request origin, and Vary: Origin is added.
    allowCredentials: bool = false,

    /// Number of seconds the results of a preflight request can be cached by browsers and proxies.
    /// Default: 86400 (24 hours). If null or 0, no max-age header is emitted.
    maxAge: ?u32 = 86400,

    /// HTTP status code to return for successful preflight OPTIONS requests.
    /// Default: .no_content (204). Can be set to .ok (200) for legacy browser support.
    optionsSuccessStatus: std.http.Status = .no_content,
};

/// Matches an origin string against an allowed origin pattern.
/// Supported patterns:
/// - `"*"`: matches any origin.
/// - Exact match: `"https://example.com"` == `"https://example.com"`.
/// - Wildcard in pattern: `"http://localhost:*"` matches any port on localhost like `"http://localhost:3000"` or `"http://localhost:5173"`.
/// - Subdomain wildcard: `"*.example.com"` or `"https://*.example.com"` matches `"https://api.example.com"`.
pub fn matchOriginPattern(pattern: []const u8, origin: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.eql(u8, pattern, origin)) return true;
    if (std.mem.indexOfScalar(u8, pattern, '*')) |star_idx| {
        const prefix = pattern[0..star_idx];
        const suffix = pattern[star_idx + 1 ..];
        if (origin.len < prefix.len + suffix.len) return false;
        return std.mem.startsWith(u8, origin, prefix) and std.mem.endsWith(u8, origin, suffix);
    }
    return false;
}

/// Checks whether an origin is allowed according to the configured CorsOptions.
pub fn isOriginAllowed(comptime opts: CorsOptions, origin: []const u8) bool {
    if (opts.allowOriginFn) |func| {
        if (func(origin)) return true;
    }
    if (opts.origins.len > 0) {
        for (opts.origins) |pattern| {
            if (matchOriginPattern(pattern, origin)) return true;
        }
        return false;
    }
    return matchOriginPattern(opts.origin, origin);
}

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

/// Creates a production-grade CORS middleware with custom or default options.
/// Conforms strictly to W3C Cross-Origin Resource Sharing (CORS) and WHATWG Fetch specifications:
/// - Automatically handles OPTIONS preflight requests by replying with 204 No Content (configurable).
/// - Preserves and merges all headers through Response.send() and Response.sendWithHeaders().
/// - Supports origin whitelisting with wildcard subdomains and ports (*.example.com, http://localhost:*).
/// - Enforces credential safety: never emits wildcard '*' origin when allowCredentials is true.
/// - Dynamically reflects Access-Control-Request-Headers when headers = "*" for credential compatibility.
/// - Adds Vary: Origin and preflight Vary headers to prevent proxy/CDN cache poisoning.
pub fn cors(comptime options: CorsOptions) MiddlewareFn {
    const max_age_str: ?[]const u8 = if (options.maxAge) |age|
        if (age > 0) std.fmt.comptimePrint("{d}", .{age}) else null
    else
        null;

    return struct {
        fn handle(req: *Request, res: *Response) anyerror!bool {
            const maybe_origin = req.getHeader("origin");
            const is_options = (req.method() == .OPTIONS);

            if (maybe_origin) |origin_hdr| {
                const allowed = isOriginAllowed(options, origin_hdr);

                if (is_options) {
                    if (!allowed) {
                        try res.send("", .{ .status = .forbidden });
                        return false;
                    }

                    const allow_origin = if (options.allowCredentials)
                        origin_hdr
                    else if (options.origins.len > 0)
                        origin_hdr
                    else if (std.mem.eql(u8, options.origin, "*"))
                        "*"
                    else
                        origin_hdr;

                    try res.setHeader("access-control-allow-origin", allow_origin);
                    try res.setHeader("access-control-allow-methods", options.methods);

                    // Dynamic header reflection
                    if (std.mem.eql(u8, options.headers, "*")) {
                        if (req.getHeader("access-control-request-headers")) |req_hdrs| {
                            try res.setHeader("access-control-allow-headers", req_hdrs);
                        } else {
                            if (options.allowCredentials) {
                                try res.setHeader("access-control-allow-headers", "Accept, Authorization, Content-Type, Origin, X-Requested-With");
                            } else {
                                try res.setHeader("access-control-allow-headers", "*");
                            }
                        }
                    } else {
                        try res.setHeader("access-control-allow-headers", options.headers);
                    }

                    if (options.allowCredentials) {
                        try res.setHeader("access-control-allow-credentials", "true");
                    }

                    if (options.exposeHeaders.len > 0) {
                        try res.setHeader("access-control-expose-headers", options.exposeHeaders);
                    }

                    if (max_age_str) |age_val| {
                        try res.setHeader("access-control-max-age", age_val);
                    }

                    try res.setHeader("vary", "Origin, Access-Control-Request-Method, Access-Control-Request-Headers");
                    try res.send("", .{ .status = options.optionsSuccessStatus });
                    return false;
                }

                // Actual request (GET, POST, PUT, DELETE, PATCH, etc.)
                if (allowed) {
                    const allow_origin = if (options.allowCredentials)
                        origin_hdr
                    else if (options.origins.len > 0)
                        origin_hdr
                    else if (std.mem.eql(u8, options.origin, "*"))
                        "*"
                    else
                        origin_hdr;

                    try res.setHeader("access-control-allow-origin", allow_origin);

                    if (options.allowCredentials) {
                        try res.setHeader("access-control-allow-credentials", "true");
                    }

                    if (options.exposeHeaders.len > 0) {
                        try res.setHeader("access-control-expose-headers", options.exposeHeaders);
                    }

                    if (!std.mem.eql(u8, allow_origin, "*") or options.allowCredentials) {
                        try res.setHeader("vary", "Origin");
                    }
                }
                return true;
            }

            // Request without Origin header
            if (is_options) {
                if (std.mem.eql(u8, options.origin, "*") and options.origins.len == 0 and !options.allowCredentials) {
                    try res.setHeader("access-control-allow-origin", "*");
                    try res.setHeader("access-control-allow-methods", options.methods);
                    try res.setHeader("access-control-allow-headers", if (std.mem.eql(u8, options.headers, "*")) "*" else options.headers);
                    if (options.exposeHeaders.len > 0) {
                        try res.setHeader("access-control-expose-headers", options.exposeHeaders);
                    }
                    if (max_age_str) |age_val| {
                        try res.setHeader("access-control-max-age", age_val);
                    }
                    try res.setHeader("vary", "Origin");
                    try res.send("", .{ .status = options.optionsSuccessStatus });
                    return false;
                }
                return true;
            }

            // Normal non-CORS request without Origin header
            if (std.mem.eql(u8, options.origin, "*") and options.origins.len == 0 and !options.allowCredentials) {
                try res.setHeader("access-control-allow-origin", "*");
                if (options.exposeHeaders.len > 0) {
                    try res.setHeader("access-control-expose-headers", options.exposeHeaders);
                }
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
