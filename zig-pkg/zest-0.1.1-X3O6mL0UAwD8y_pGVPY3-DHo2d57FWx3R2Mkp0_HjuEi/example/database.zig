const std = @import("std");
const zest = @import("zest");

pub var db: zest.Db = undefined;

/// Initializes the application database from a URL (SQLite file, Supabase PostgreSQL, or MongoDB).
pub fn init(allocator: std.mem.Allocator, url: []const u8) !void {
    db = try zest.Db.connect(allocator, url);
}

/// Frees database resources and closes connections.
pub fn deinit() void {
    db.deinit();
}
