const std = @import("std");
const Request = @import("request.zig");
const Response = @import("response.zig");

prefix: []const u8,
dir: []const u8,

const Self = @This();
const max_file_size: usize = 20 * 1024 * 1024; // 20 MB max static file

/// Returns the standard MIME content-type based on file extension.
pub fn mimeType(ext: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(ext, ".html") or std.ascii.eqlIgnoreCase(ext, ".htm")) {
        return "text/html; charset=utf-8";
    } else if (std.ascii.eqlIgnoreCase(ext, ".css")) {
        return "text/css; charset=utf-8";
    } else if (std.ascii.eqlIgnoreCase(ext, ".js") or std.ascii.eqlIgnoreCase(ext, ".mjs")) {
        return "application/javascript; charset=utf-8";
    } else if (std.ascii.eqlIgnoreCase(ext, ".json")) {
        return "application/json; charset=utf-8";
    } else if (std.ascii.eqlIgnoreCase(ext, ".png")) {
        return "image/png";
    } else if (std.ascii.eqlIgnoreCase(ext, ".jpg") or std.ascii.eqlIgnoreCase(ext, ".jpeg")) {
        return "image/jpeg";
    } else if (std.ascii.eqlIgnoreCase(ext, ".gif")) {
        return "image/gif";
    } else if (std.ascii.eqlIgnoreCase(ext, ".svg")) {
        return "image/svg+xml";
    } else if (std.ascii.eqlIgnoreCase(ext, ".ico")) {
        return "image/x-icon";
    } else if (std.ascii.eqlIgnoreCase(ext, ".wasm")) {
        return "application/wasm";
    } else if (std.ascii.eqlIgnoreCase(ext, ".txt")) {
        return "text/plain; charset=utf-8";
    }
    return "application/octet-stream";
}

/// Attempts to serve a static file from disk matching this static handler's prefix and directory.
pub fn serve(
    self: *const Self,
    io: std.Io,
    allocator: std.mem.Allocator,
    req: *Request,
    res: *Response,
) !bool {
    // Static files only respond to GET and HEAD requests
    if (req.method() != .GET and req.method() != .HEAD) {
        return false;
    }

    const req_path = req.path();

    // Must match or start with prefix
    if (!std.mem.startsWith(u8, req_path, self.prefix)) {
        return false;
    }

    const rel_path = req_path[self.prefix.len..];
    const clean_rel = if (std.mem.startsWith(u8, rel_path, "/")) rel_path[1..] else rel_path;
    const final_rel = if (clean_rel.len == 0) "index.html" else clean_rel;

    // Security check: prevent directory traversal
    if (std.mem.indexOf(u8, final_rel, "..") != null) {
        return false;
    }

    const full_file_path = try std.fs.path.join(allocator, &.{ self.dir, final_rel });
    defer allocator.free(full_file_path);

    var file = std.Io.Dir.cwd().openFile(io, full_file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    defer file.close(io);

    const stat = file.stat(io) catch return false;
    if (stat.size > max_file_size) return false;

    const file_len: usize = @intCast(stat.size);
    const content = allocator.alloc(u8, file_len) catch return false;
    defer allocator.free(content);

    _ = file.readPositionalAll(io, content, 0) catch return false;

    const ext = std.fs.path.extension(final_rel);
    const content_type = mimeType(ext);

    try res.send(content, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = content_type },
        },
    });

    return true;
}
