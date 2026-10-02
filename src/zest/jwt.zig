const std = @import("std");

const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
const b64_encoder = std.base64.url_safe_no_pad.Encoder;
const b64_decoder = std.base64.url_safe_no_pad.Decoder;

const default_header_b64 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";

pub const JwtError = error{
    MalformedToken,
    InvalidSignature,
    ExpiredToken,
    OutOfMemory,
};

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

/// Signs a JSON string or any Zig struct/payload with the given secret key using HMAC-SHA256 (HS256).
/// Caller owns the returned token slice.
pub fn sign(allocator: std.mem.Allocator, payload: anytype, secret: []const u8) ![]u8 {
    const T = @TypeOf(payload);
    const payload_json: []const u8 = if (comptime isString(T))
        asStringSlice(payload)
    else
        try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer {
        if (comptime !isString(T)) {
            allocator.free(payload_json);
        }
    }

    const payload_b64_len = b64_encoder.calcSize(payload_json.len);
    const payload_b64 = try allocator.alloc(u8, payload_b64_len);
    defer allocator.free(payload_b64);
    _ = b64_encoder.encode(payload_b64, payload_json);

    // Message to sign is: default_header_b64 ++ "." ++ payload_b64
    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ default_header_b64, payload_b64 });
    defer allocator.free(signing_input);

    var mac: [Hmac.mac_length]u8 = undefined;
    Hmac.create(&mac, signing_input, secret);

    const sig_b64_len = b64_encoder.calcSize(mac.len);
    const sig_b64 = try allocator.alloc(u8, sig_b64_len);
    defer allocator.free(sig_b64);
    _ = b64_encoder.encode(sig_b64, &mac);

    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ signing_input, sig_b64 });
}

/// Verifies a JWT token signature and returns the decoded JSON payload string.
/// Caller owns the returned payload slice.
pub fn verify(allocator: std.mem.Allocator, token: []const u8, secret: []const u8) JwtError![]u8 {
    var iter = std.mem.splitScalar(u8, token, '.');
    const header_b64 = iter.next() orelse return error.MalformedToken;
    const payload_b64 = iter.next() orelse return error.MalformedToken;
    const sig_b64 = iter.next() orelse return error.MalformedToken;

    if (iter.next() != null) {
        return error.MalformedToken;
    }

    // Verify signature
    const signing_input = std.fmt.allocPrint(allocator, "{s}.{s}", .{ header_b64, payload_b64 }) catch return error.OutOfMemory;
    defer allocator.free(signing_input);

    var expected_mac: [Hmac.mac_length]u8 = undefined;
    Hmac.create(&expected_mac, signing_input, secret);

    const decoded_sig_len = b64_decoder.calcSizeForSlice(sig_b64) catch return error.MalformedToken;
    if (decoded_sig_len != Hmac.mac_length) {
        return error.InvalidSignature;
    }

    var actual_mac: [Hmac.mac_length]u8 = undefined;
    b64_decoder.decode(&actual_mac, sig_b64) catch return error.MalformedToken;

    var diff: u8 = 0;
    for (expected_mac, actual_mac) |a, b| {
        diff |= a ^ b;
    }
    if (diff != 0) {
        return error.InvalidSignature;
    }

    // Decode payload
    const payload_len = b64_decoder.calcSizeForSlice(payload_b64) catch return error.MalformedToken;
    const payload = allocator.alloc(u8, payload_len) catch return error.OutOfMemory;
    errdefer allocator.free(payload);

    b64_decoder.decode(payload, payload_b64) catch return error.MalformedToken;

    return payload;
}

/// Verifies a JWT token signature and parses the decoded JSON payload into a Zig struct `T`.
pub fn verifyAs(comptime T: type, allocator: std.mem.Allocator, token: []const u8, secret: []const u8) !std.json.Parsed(T) {
    const payload = try verify(allocator, token, secret);
    defer allocator.free(payload);
    return try std.json.parseFromSlice(T, allocator, payload, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}
