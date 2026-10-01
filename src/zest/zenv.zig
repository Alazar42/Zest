const std = @import("std");
const builtin = @import("builtin");

/// In-memory storage for environment variables loaded by zenv.
var env_map: std.StringHashMap([]const u8) = undefined;
var is_initialized: bool = false;
var map_allocator: ?std.mem.Allocator = null;

/// Ensures the global environment map is initialized.
fn ensureInit(allocator: std.mem.Allocator) void {
    if (!is_initialized) {
        env_map = std.StringHashMap([]const u8).init(allocator);
        is_initialized = true;
        map_allocator = allocator;
    }
}

/// Frees all parsed keys, values, and the environment map.
pub fn deinit() void {
    if (is_initialized) {
        if (map_allocator) |alloc| {
            var iter = env_map.iterator();
            while (iter.next()) |entry| {
                alloc.free(entry.key_ptr.*);
                alloc.free(entry.value_ptr.*);
            }
            env_map.deinit();
        }
        is_initialized = false;
        map_allocator = null;
    }
}

/// Sets an environment variable in zenv.
pub fn set(allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    ensureInit(allocator);
    const k_dup = try allocator.dupe(u8, key);
    errdefer allocator.free(k_dup);
    const v_dup = try allocator.dupe(u8, value);
    errdefer allocator.free(v_dup);

    if (env_map.fetchRemove(key)) |old| {
        allocator.free(old.key);
        allocator.free(old.value);
    }
    try env_map.put(k_dup, v_dup);
}

/// Retrieves an environment variable. First checks zenv loaded values,
/// then falls back to the host system environment (like python-dotenv).
var proc_env_buf: [16384]u8 = undefined;
var proc_env_len: usize = 0;
var proc_env_loaded: bool = false;

fn getEnvFromOs(key: []const u8) ?[]const u8 {
    if (builtin.os.tag == .linux) {
        if (!proc_env_loaded) {
            proc_env_loaded = true;
            const fd = std.os.linux.open("/proc/self/environ", .{}, 0);
            if (fd >= 0) {
                defer _ = std.os.linux.close(@intCast(fd));
                const n = std.os.linux.read(@intCast(fd), &proc_env_buf, proc_env_buf.len);
                if (n > 0) {
                    proc_env_len = @intCast(n);
                }
            }
        }
        if (proc_env_len > 0) {
            var start: usize = 0;
            while (start < proc_env_len) {
                const rest = proc_env_buf[start..proc_env_len];
                const end = std.mem.indexOfScalar(u8, rest, 0) orelse rest.len;
                const entry = rest[0..end];
                if (std.mem.indexOfScalar(u8, entry, '=')) |eq_pos| {
                    if (std.mem.eql(u8, entry[0..eq_pos], key)) {
                        return entry[eq_pos + 1 ..];
                    }
                }
                start += end + 1;
            }
        }
    }
    return null;
}

/// Retrieves an environment variable. First checks zenv loaded values,
/// then falls back to the host system environment (like python-dotenv).
pub fn get(key: []const u8) ?[]const u8 {
    if (is_initialized) {
        if (env_map.get(key)) |val| {
            return val;
        }
    }
    return getEnvFromOs(key);
}

/// Retrieves an environment variable or returns the default value if unset.
pub fn getOr(key: []const u8, default_value: []const u8) []const u8 {
    return get(key) orelse default_value;
}

/// Retrieves an environment variable and parses it into an integer type `T`.
pub fn getInt(key: []const u8, comptime T: type) ?T {
    const raw = get(key) orelse return null;
    return std.fmt.parseInt(T, raw, 10) catch null;
}

/// Retrieves an environment variable and parses it into a boolean.
/// Matches "1", "true", "True", "TRUE", "yes", "YES", "on", "ON".
pub fn getBool(key: []const u8) bool {
    const raw = get(key) orelse return false;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    return std.mem.eql(u8, trimmed, "1") or
        std.ascii.eqlIgnoreCase(trimmed, "true") or
        std.ascii.eqlIgnoreCase(trimmed, "yes") or
        std.ascii.eqlIgnoreCase(trimmed, "on");
}

/// Parses the contents of a .env file into the environment map.
pub fn parse(allocator: std.mem.Allocator, contents: []const u8) !void {
    ensureInit(allocator);

    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        // Support 'export KEY=VALUE'
        if (std.mem.startsWith(u8, line, "export ")) {
            line = std.mem.trim(u8, line[7..], " \t");
        }

        const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_pos], " \t");
        if (key.len == 0) continue;

        var raw_val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");

        if (raw_val.len >= 2 and raw_val[0] == '"' and raw_val[raw_val.len - 1] == '"') {
            // Double-quoted string: unescape \n, \t, \r, \", \\
            const inside = raw_val[1 .. raw_val.len - 1];
            var unescaped: std.ArrayList(u8) = .empty;
            defer unescaped.deinit(allocator);

            var i: usize = 0;
            while (i < inside.len) {
                if (inside[i] == '\\' and i + 1 < inside.len) {
                    switch (inside[i + 1]) {
                        'n' => try unescaped.append(allocator, '\n'),
                        't' => try unescaped.append(allocator, '\t'),
                        'r' => try unescaped.append(allocator, '\r'),
                        '\"' => try unescaped.append(allocator, '\"'),
                        '\\' => try unescaped.append(allocator, '\\'),
                        else => {
                            try unescaped.append(allocator, '\\');
                            try unescaped.append(allocator, inside[i + 1]);
                        },
                    }
                    i += 2;
                } else {
                    try unescaped.append(allocator, inside[i]);
                    i += 1;
                }
            }
            try set(allocator, key, unescaped.items);
        } else if (raw_val.len >= 2 and raw_val[0] == '\'' and raw_val[raw_val.len - 1] == '\'') {
            // Single-quoted string: verbatim
            try set(allocator, key, raw_val[1 .. raw_val.len - 1]);
        } else {
            // Unquoted string: strip trailing comment if any
            if (std.mem.indexOfScalar(u8, raw_val, '#')) |comment_idx| {
                raw_val = std.mem.trim(u8, raw_val[0..comment_idx], " \t");
            }
            try set(allocator, key, raw_val);
        }
    }
}

const c = struct {
    pub extern "c" fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
    pub extern "c" fn fclose(stream: ?*anyopaque) c_int;
    pub extern "c" fn fseek(stream: ?*anyopaque, offset: c_long, whence: c_int) c_int;
    pub extern "c" fn ftell(stream: ?*anyopaque) c_long;
    pub extern "c" fn fread(ptr: ?*anyopaque, size: usize, n: usize, stream: ?*anyopaque) usize;
};

/// Reads a .env file from disk.
fn readLocalFile(allocator: std.mem.Allocator, filepath: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, filepath);
    defer allocator.free(path_z);

    const fp = c.fopen(path_z, "rb") orelse return error.FileNotFound;
    defer _ = c.fclose(fp);

    _ = c.fseek(fp, 0, 2); // SEEK_END
    const size = c.ftell(fp);
    _ = c.fseek(fp, 0, 0); // SEEK_SET

    if (size < 0) return error.CannotStat;
    const usize_size: usize = @intCast(size);

    const buf = try allocator.alloc(u8, usize_size);
    errdefer allocator.free(buf);

    const n = c.fread(buf.ptr, 1, usize_size, fp);
    return buf[0..n];
}

/// Loads a specific .env file by its filepath.
pub fn loadFile(allocator: std.mem.Allocator, filepath: []const u8) !void {
    const contents = try readLocalFile(allocator, filepath);
    defer allocator.free(contents);
    try parse(allocator, contents);
}

/// Automatically searches for and loads `.env` in the current working directory.
/// If the file does not exist, it quietly proceeds without failing (matching python-dotenv).
pub fn load(allocator: std.mem.Allocator) !void {
    loadFile(allocator, ".env") catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}
