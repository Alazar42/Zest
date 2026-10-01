const std = @import("std");
const builtin = @import("builtin");
const time = @import("time.zig");

/// Generates a random UUID v4 string (RFC 4122 compliant) into the provided 36-byte buffer.
/// Format: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
pub fn v4(buf: *[36]u8) []const u8 {
    var bytes: [16]u8 = undefined;

    if (builtin.os.tag == .linux) {
        _ = std.os.linux.getrandom(&bytes, bytes.len, 0);
    } else {
        var seed: u128 = @bitCast(time.nanoTimestamp());
        for (&bytes, 0..) |*b, i| {
            seed ^= seed >> 13;
            seed ^= seed << 7;
            seed ^= seed >> 17;
            b.* = @truncate((seed >> @intCast((i % 8) * 8)) & 0xff);
        }
    }

    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 10
    const hex = "0123456789abcdef";
    var out_idx: usize = 0;
    for (bytes, 0..) |b, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            buf[out_idx] = '-';
            out_idx += 1;
        }
        buf[out_idx] = hex[b >> 4];
        out_idx += 1;
        buf[out_idx] = hex[b & 0x0f];
        out_idx += 1;
    }
    return buf[0..36];
}

/// Allocates and returns a fresh UUID v4 string.
pub fn v4Alloc(allocator: std.mem.Allocator) ![]u8 {
    var buf: [36]u8 = undefined;
    const str = v4(&buf);
    return allocator.dupe(u8, str);
}
