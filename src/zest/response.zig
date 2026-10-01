const std = @import("std");
const Request = @import("request.zig");
pub const Cookie = @import("cookie.zig");

server_request: *std.http.Server.Request,
request: ?*Request = null,
headers: std.ArrayList(std.http.Header) = .empty,
status_code: std.http.Status = .ok,
log_enabled: bool = false,

const Self = @This();

/// Releases any buffered header allocations.
pub fn deinit(self: *Self) void {
    if (self.request) |r| {
        self.headers.deinit(r.allocator);
    }
}

/// Sets an HTTP response header.
pub fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    try self.headers.append(allocator, .{ .name = name, .value = value });
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

/// Responds with text/plain content and HTTP 200 OK.
pub fn text(self: *Self, content: []const u8) !void {
    try self.sendWithHeaders(content, .ok, "text/plain; charset=utf-8");
}

/// Responds with application/json raw string and HTTP 200 OK.
pub fn json(self: *Self, content: []const u8) !void {
    try self.sendWithHeaders(content, .ok, "application/json; charset=utf-8");
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
pub fn jsonValue(self: *Self, val: anytype) !void {
    const allocator = if (self.request) |r| r.allocator else std.heap.page_allocator;
    const json_str = try serializeJson(allocator, val);
    defer allocator.free(json_str);
    try self.json(json_str);
}

/// Responds with text/html content and HTTP 200 OK.
pub fn html(self: *Self, content: []const u8) !void {
    try self.sendWithHeaders(content, .ok, "text/html; charset=utf-8");
}

/// Responds with a custom status code and content.
pub fn status(self: *Self, http_status: std.http.Status, content: []const u8) !void {
    try self.sendWithHeaders(content, http_status, "text/plain; charset=utf-8");
}

/// Sends an HTTP 302 Found redirect to the specified URL location.
pub fn redirect(self: *Self, location: []const u8) !void {
    try self.setHeader("location", location);
    try self.sendWithHeaders("", .found, "");
}

/// Sends a response with custom RespondOptions (headers, status, etc.).
pub fn send(self: *Self, content: []const u8, options: std.http.Server.Request.RespondOptions) !void {
    self.status_code = options.status;
    try self.server_request.respond(content, options);
}
