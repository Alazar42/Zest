const std = @import("std");
const Response = @import("response.zig");
const Param = @import("param.zig");
const time = @import("time.zig");
const validation = @import("validation.zig");
const background = @import("background.zig");
const multipart_mod = @import("multipart.zig");

server_request: *std.http.Server.Request,
allocator: std.mem.Allocator,
io: std.Io,
params: [16]Param = undefined,
params_len: usize = 0,
response: ?*Response = null,
start_time: i128 = 0,
req_method: std.http.Method = .GET,
target_buf: [1024]u8 = undefined,
target_len: usize = 0,
path_len: usize = 0,
auth_user: ?[]const u8 = null,
auth_claims: ?[]const u8 = null,
background_tasks: background.BackgroundTasks,

const Self = @This();

/// Initializes a Request, copying the target URI safely to prevent memory invalidation when reading body buffers.
pub fn init(server_request: *std.http.Server.Request, allocator: std.mem.Allocator, io: std.Io) Self {
    var self: Self = .{
        .server_request = server_request,
        .allocator = allocator,
        .io = io,
        .start_time = time.getMonotonicNanos(),
        .req_method = server_request.head.method,
        .background_tasks = background.BackgroundTasks.init(allocator),
    };
    const raw = server_request.head.target;
    const len = @min(raw.len, self.target_buf.len);
    @memcpy(self.target_buf[0..len], raw[0..len]);
    self.target_len = len;
    self.path_len = if (std.mem.indexOfScalar(u8, self.target_buf[0..len], '?')) |idx| idx else len;
    return self;
}

/// Returns the elapsed duration since request processing began, in nanoseconds.
pub fn elapsedNanos(self: *const Self) i128 {
    if (self.start_time == 0) return 0;
    return time.getMonotonicNanos() - self.start_time;
}

/// Returns the HTTP method of the request.
pub fn method(self: *const Self) std.http.Method {
    return self.req_method;
}

/// Returns the full raw target URI (e.g. "/items?sort=asc").
pub fn target(self: *const Self) []const u8 {
    return self.target_buf[0..self.target_len];
}

/// Returns the path portion of the URL target (excluding query string).
pub fn path(self: *const Self) []const u8 {
    return self.target_buf[0..self.path_len];
}

/// Returns the query string portion if present (e.g. "key=value").
pub fn query(self: *const Self) ?[]const u8 {
    if (self.path_len < self.target_len) {
        return self.target_buf[self.path_len + 1 .. self.target_len];
    }
    return null;
}

/// Retrieves a matched dynamic path parameter by name (e.g. ":id" -> "42").
pub fn param(self: *const Self, name: []const u8) ?[]const u8 {
    for (self.params[0..self.params_len]) |p| {
        if (std.mem.eql(u8, p.name, name)) {
            return p.value;
        }
    }
    return null;
}

/// Parses a matched dynamic path parameter directly into an integer type `T`.
pub fn paramInt(self: *const Self, name: []const u8, comptime T: type) ?T {
    const val_str = self.param(name) orelse return null;
    return std.fmt.parseInt(T, val_str, 10) catch null;
}

/// Retrieves the raw value for a given query parameter key (e.g. "?limit=10" -> "10").
pub fn queryParam(self: *const Self, name: []const u8) ?[]const u8 {
    const q = self.query() orelse return null;
    var iter = std.mem.splitScalar(u8, q, '&');
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_idx| {
            const key = pair[0..eq_idx];
            if (std.mem.eql(u8, key, name)) {
                return pair[eq_idx + 1 ..];
            }
        } else {
            if (std.mem.eql(u8, pair, name)) {
                return "";
            }
        }
    }
    return null;
}

/// Retrieves and percent-decodes a query parameter value into newly allocated memory.
pub fn queryParamDecoded(self: *Self, name: []const u8) !?[]u8 {
    const raw = self.queryParam(name) orelse return null;
    return try decodeUrl(self.allocator, raw);
}

/// Finds and returns the first header value matching the case-insensitive name.
pub fn getHeader(self: *const Self, name: []const u8) ?[]const u8 {
    var iter = self.server_request.iterateHeaders();
    while (iter.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) {
            return h.value;
        }
    }
    return null;
}

/// Alias for `getHeader`.
pub fn header(self: *const Self, name: []const u8) ?[]const u8 {
    return self.getHeader(name);
}

/// Returns the request content-type header if present.
pub fn contentType(self: *const Self) ?[]const u8 {
    return self.getHeader("content-type");
}

/// Retrieves a cookie value by name from the `Cookie: a=b; c=d` header.
pub fn cookie(self: *const Self, name: []const u8) ?[]const u8 {
    const raw = self.getHeader("cookie") orelse return null;
    var iter = std.mem.splitSequence(u8, raw, "; ");
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_idx| {
            const k = std.mem.trim(u8, pair[0..eq_idx], " ");
            if (std.mem.eql(u8, k, name)) {
                return pair[eq_idx + 1 ..];
            }
        }
    }
    return null;
}

/// Extracts Bearer token from the `Authorization: Bearer <token>` header.
pub fn bearerToken(self: *const Self) ?[]const u8 {
    const auth = self.getHeader("authorization") orelse return null;
    if (auth.len > 7 and std.ascii.eqlIgnoreCase(auth[0..7], "bearer ")) {
        return std.mem.trim(u8, auth[7..], " ");
    }
    return null;
}

/// Reads the entire request body up to `max_size` bytes allocated with `self.allocator`.
/// Caller owns the returned slice and must free it with `self.allocator.free(slice)`.
pub fn readBodyAlloc(self: *Self, max_size: usize) ![]u8 {
    var transfer_buf: [1024]u8 = undefined;
    const body_reader = try self.server_request.readerExpectContinue(&transfer_buf);
    return try body_reader.allocRemaining(self.allocator, std.Io.Limit.limited(max_size));
}

/// Parses the request body JSON directly into a Zig type `T` (or Model).
/// Free the returned parsed value with `parsed.deinit()`.
pub fn parseJson(self: *Self, comptime T: type) !std.json.Parsed(T) {
    const body = try self.readBodyAlloc(1024 * 1024);
    defer self.allocator.free(body);
    return try std.json.parseFromSlice(T, self.allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

/// Parses and validates the request body JSON against struct rules (e.g. `pub fn validate(...)`).
/// If invalid, automatically sends HTTP 422 Unprocessable Entity with field errors and returns null.
pub fn validateJson(self: *Self, comptime T: type, res: *Response) !?std.json.Parsed(T) {
    const body = self.readBodyAlloc(1024 * 1024) catch {
        try res.status(.unprocessable_entity, .{
            .detail = &[_]struct { field: []const u8, message: []const u8 }{
                .{ .field = "body", .message = "Could not read request body" },
            },
        });
        return null;
    };
    defer self.allocator.free(body);

    const parsed = std.json.parseFromSlice(T, self.allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch {
        try res.status(.unprocessable_entity, .{
            .detail = &[_]struct { field: []const u8, message: []const u8 }{
                .{ .field = "body", .message = "Malformed JSON payload" },
            },
        });
        return null;
    };

    if (@hasDecl(T, "validate")) {
        var validation_errs = validation.ValidationErrors.init(self.allocator);
        defer validation_errs.deinit();

        parsed.value.validate(&validation_errs);
        if (validation_errs.hasErrors()) {
            try res.status(.unprocessable_entity, .{ .detail = validation_errs.errors.items });
            parsed.deinit();
            return null;
        }
    }

    return parsed;
}

/// Returns the authenticated username or user ID injected by JWT auth middleware.
pub fn user(self: *const Self) ?[]const u8 {
    return self.auth_user;
}

/// Returns the raw claims payload injected by JWT auth middleware.
pub fn authPayload(self: *const Self) ?[]const u8 {
    return self.auth_claims;
}

/// Adds an asynchronous task to be executed in the background after the response is sent.
pub fn addBackgroundTask(self: *Self, func: background.TaskFn, ctx: ?*anyopaque) !void {
    try self.background_tasks.add(func, ctx);
}

/// Parses multipart/form-data fields and file uploads from the request body.
pub fn multipart(self: *Self) !multipart_mod.FormData {
    const ct = self.contentType() orelse return error.MissingContentType;
    const boundary = multipart_mod.extractBoundary(ct) orelse return error.MissingBoundary;
    const body = try self.readBodyAlloc(50 * 1024 * 1024); // 50MB max upload
    defer self.allocator.free(body);
    return multipart_mod.parse(self.allocator, body, boundary);
}

/// Cleans up any resources associated with the Request.
pub fn deinit(self: *Self) void {
    self.background_tasks.deinit();
}

/// Helper function to percent-decode a URL-encoded string.
pub fn decodeUrl(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, input.len);
    var out_i: usize = 0;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hex_byte = std.fmt.parseInt(u8, input[i + 1 .. i + 3], 16) catch null;
            if (hex_byte) |b| {
                out[out_i] = b;
                out_i += 1;
                i += 3;
                continue;
            }
        } else if (input[i] == '+') {
            out[out_i] = ' ';
            out_i += 1;
            i += 1;
            continue;
        }
        out[out_i] = input[i];
        out_i += 1;
        i += 1;
    }
    return allocator.realloc(out, out_i);
}
