const std = @import("std");
const Request = @import("request.zig");
pub const Cookie = @import("cookie.zig");

server_request: *std.http.Server.Request,
request: ?*Request = null,
headers: std.ArrayList(std.http.Header) = .empty,
status_code: std.http.Status = .ok,
log_enabled: bool = false,
sent: bool = false,

const Self = @This();

/// Releases any buffered header allocations.
pub fn deinit(self: *Self) void {
    if (self.request) |r| {
        self.headers.deinit(r.allocator);
    }
}

/// Sets an HTTP response header. Replaces any existing header with the same name (case-insensitive),
/// except for "set-cookie", which allows multiple entries.
pub fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    if (!std.ascii.eqlIgnoreCase(name, "set-cookie")) {
        for (self.headers.items) |*h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                h.value = value;
                return;
            }
        }
    }
    try self.headers.append(allocator, .{ .name = name, .value = value });
}

/// Appends an HTTP response header without replacing existing entries.
pub fn appendHeader(self: *Self, name: []const u8, value: []const u8) !void {
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    try self.headers.append(allocator, .{ .name = name, .value = value });
}

/// Retrieves the value of a buffered response header by name (case-insensitive).
pub fn getHeader(self: *const Self, name: []const u8) ?[]const u8 {
    for (self.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) {
            return h.value;
        }
    }
    return null;
}

/// Sets a Set-Cookie header using the Cookie configuration.
pub fn setCookie(self: *Self, c: Cookie) !void {
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    const cookie_str = try c.serialize(allocator);
    try self.setHeader("set-cookie", cookie_str);
}

/// Internal helper to respond with custom status, default content-type, and all buffered headers.
pub fn sendWithHeaders(self: *Self, content: []const u8, http_status: std.http.Status, content_type: []const u8) !void {
    self.status_code = http_status;
    self.sent = true;
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    var out_headers: std.ArrayList(std.http.Header) = .empty;
    defer out_headers.deinit(allocator);

    // Check if content-type was already overridden in headers
    var has_content_type = false;
    for (self.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-type")) {
            has_content_type = true;
            break;
        }
    }
    if (!has_content_type and content_type.len > 0) {
        try out_headers.append(allocator, .{ .name = "content-type", .value = content_type });
    }
    try out_headers.appendSlice(allocator, self.headers.items);

    try self.server_request.respond(content, .{
        .status = http_status,
        .extra_headers = out_headers.items,
    });
}

fn isString(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                return ptr.child == u8;
            } else if (ptr.size == .one) {
                return switch (@typeInfo(ptr.child)) {
                    .array => |arr| arr.child == u8,
                    else => false,
                };
            }
            return false;
        },
        .array => |arr| {
            return arr.child == u8;
        },
        else => return false,
    }
}

fn asStringSlice(val: anytype) []const u8 {
    const T = @TypeOf(val);
    if (comptime isString(T)) {
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    return val;
                } else if (ptr.size == .one) {
                    return val[0..];
                }
            },
            .array => return val[0..],
            else => unreachable,
        }
    }
    unreachable;
}

/// Responds with text/plain content and HTTP 200 OK.
pub fn text(self: *Self, content: []const u8) !void {
    try self.sendWithHeaders(content, .ok, "text/plain; charset=utf-8");
}

/// Responds with application/json and HTTP 200 OK.
/// Accepts either a raw JSON string/slice or any Zig struct, Model, or value to serialize.
pub fn json(self: *Self, val: anytype) !void {
    const T = @TypeOf(val);
    if (comptime isString(T)) {
        const slice = asStringSlice(val);
        try self.sendWithHeaders(slice, .ok, "application/json; charset=utf-8");
    } else {
        const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
        const json_str = try serializeJson(allocator, val);
        defer allocator.free(json_str);
        try self.sendWithHeaders(json_str, .ok, "application/json; charset=utf-8");
    }
}

fn isParsed(comptime T: type) bool {
    const Actual = switch (@typeInfo(T)) {
        .pointer => |ptr| if (ptr.size == .one) ptr.child else return false,
        else => T,
    };
    if (@typeInfo(Actual) == .@"struct") {
        return @hasField(Actual, "arena") and @hasField(Actual, "value");
    }
    return false;
}

fn isParsedSlice(comptime T: type) bool {
    var Current = T;
    while (@typeInfo(Current) == .pointer and @typeInfo(Current).pointer.size == .one) {
        Current = @typeInfo(Current).pointer.child;
    }
    switch (@typeInfo(Current)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                return isParsed(ptr.child);
            }
        },
        .array => |arr| {
            return isParsed(arr.child);
        },
        else => {},
    }
    return false;
}

/// Helper to serialize any Zig value, Model, Parsed(T), or slice of Parsed(T) to JSON string.
pub fn serializeJson(allocator: std.mem.Allocator, val: anytype) ![]u8 {
    const T = @TypeOf(val);

    if (comptime @typeInfo(T) == .optional) {
        if (val) |v| {
            return serializeJson(allocator, v);
        } else {
            return allocator.dupe(u8, "null");
        }
    } else if (comptime isParsed(T)) {
        return std.json.Stringify.valueAlloc(allocator, val.value, .{});
    } else if (comptime isParsedSlice(T)) {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try out.append(allocator, '[');
        for (val, 0..) |item, i| {
            if (i > 0) try out.append(allocator, ',');
            const item_json = try std.json.Stringify.valueAlloc(allocator, item.value, .{});
            defer allocator.free(item_json);
            try out.appendSlice(allocator, item_json);
        }
        try out.append(allocator, ']');
        return out.toOwnedSlice(allocator);
    } else {
        return std.json.Stringify.valueAlloc(allocator, val, .{});
    }
}

/// Automatically serializes any Zig struct, Model, slice, Parsed(T), or value to JSON and responds with HTTP 200 OK.
/// Provided for backwards compatibility with `res.json(val)`.
pub fn jsonValue(self: *Self, val: anytype) !void {
    try self.json(val);
}

/// Responds with text/html content and HTTP 200 OK.
pub fn html(self: *Self, content: []const u8) !void {
    try self.sendWithHeaders(content, .ok, "text/html; charset=utf-8");
}

/// Responds with a custom status code and content.
/// Accepts either a raw string (auto-detects JSON vs text/plain) or any Zig struct, Model, or value to serialize as JSON.
pub fn status(self: *Self, http_status: std.http.Status, val: anytype) !void {
    const T = @TypeOf(val);
    if (comptime isString(T)) {
        const slice = asStringSlice(val);
        const trimmed = std.mem.trim(u8, slice, " \t\r\n");
        const content_type = if (trimmed.len > 0 and (trimmed[0] == '{' or trimmed[0] == '['))
            "application/json; charset=utf-8"
        else
            "text/plain; charset=utf-8";
        try self.sendWithHeaders(slice, http_status, content_type);
    } else {
        const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
        const json_str = try serializeJson(allocator, val);
        defer allocator.free(json_str);
        try self.sendWithHeaders(json_str, http_status, "application/json; charset=utf-8");
    }
}

/// Sends an error JSON object `{"error": "..."}` with the specified HTTP status code.
pub fn err(self: *Self, http_status: std.http.Status, message: []const u8) !void {
    try self.status(http_status, .{ .@"error" = message });
}

/// Responds with HTTP 400 Bad Request.
pub fn badRequest(self: *Self, val: anytype) !void {
    try self.status(.bad_request, val);
}

/// Responds with HTTP 404 Not Found.
pub fn notFound(self: *Self, val: anytype) !void {
    try self.status(.not_found, val);
}

/// Responds with HTTP 401 Unauthorized.
pub fn unauthorized(self: *Self, val: anytype) !void {
    try self.status(.unauthorized, val);
}

/// Responds with HTTP 403 Forbidden.
pub fn forbidden(self: *Self, val: anytype) !void {
    try self.status(.forbidden, val);
}

/// Responds with HTTP 201 Created.
pub fn created(self: *Self, val: anytype) !void {
    try self.status(.created, val);
}

/// Responds with HTTP 500 Internal Server Error.
pub fn internalServerError(self: *Self, val: anytype) !void {
    try self.status(.internal_server_error, val);
}

/// Sends an HTTP 302 Found redirect to the specified URL location.
pub fn redirect(self: *Self, location: []const u8) !void {
    try self.setHeader("location", location);
    try self.sendWithHeaders("", .found, "");
}

/// Sends a response with custom RespondOptions (headers, status, etc.).
/// Automatically preserves and merges all buffered response headers.
pub fn send(self: *Self, content: []const u8, options: std.http.Server.Request.RespondOptions) !void {
    self.status_code = options.status;
    self.sent = true;
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    var out_headers: std.ArrayList(std.http.Header) = .empty;
    defer out_headers.deinit(allocator);

    try out_headers.appendSlice(allocator, self.headers.items);
    if (options.extra_headers.len > 0) {
        try out_headers.appendSlice(allocator, options.extra_headers);
    }
    var opts = options;
    opts.extra_headers = out_headers.items;
    try self.server_request.respond(content, opts);
}
