const std = @import("std");

pub const SameSite = enum {
    strict,
    lax,
    none,
};

name: []const u8,
value: []const u8,
path: []const u8 = "/",
domain: ?[]const u8 = null,
max_age: ?i64 = null,
http_only: bool = true,
secure: bool = false,
same_site: SameSite = .lax,

const Self = @This();

/// Formats the Set-Cookie header string into newly allocated memory.
/// Caller owns the returned slice.
pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    const base = try std.fmt.allocPrint(allocator, "{s}={s}; Path={s}", .{ self.name, self.value, self.path });
    defer allocator.free(base);
    try list.appendSlice(allocator, base);

    if (self.domain) |d| {
        const s = try std.fmt.allocPrint(allocator, "; Domain={s}", .{d});
        defer allocator.free(s);
        try list.appendSlice(allocator, s);
    }
    if (self.max_age) |ma| {
        const s = try std.fmt.allocPrint(allocator, "; Max-Age={d}", .{ma});
        defer allocator.free(s);
        try list.appendSlice(allocator, s);
    }
    if (self.http_only) {
        try list.appendSlice(allocator, "; HttpOnly");
    }
    if (self.secure) {
        try list.appendSlice(allocator, "; Secure");
    }
    switch (self.same_site) {
        .strict => try list.appendSlice(allocator, "; SameSite=Strict"),
        .lax => try list.appendSlice(allocator, "; SameSite=Lax"),
        .none => try list.appendSlice(allocator, "; SameSite=None"),
    }

    return list.toOwnedSlice(allocator);
}
