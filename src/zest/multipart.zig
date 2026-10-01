const std = @import("std");

const c = struct {
    pub extern "c" fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
    pub extern "c" fn fclose(stream: ?*anyopaque) c_int;
    pub extern "c" fn fwrite(ptr: ?*const anyopaque, size: usize, n: usize, stream: ?*anyopaque) usize;
};

pub const MultipartPart = struct {
    name: []const u8,
    filename: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    data: []const u8,

    /// Returns true if this part is a file upload with a filename.
    pub fn isFile(self: *const MultipartPart) bool {
        return self.filename != null;
    }

    /// Saves the uploaded file or data directly to a destination path on disk.
    pub fn saveTo(self: *const MultipartPart, allocator: std.mem.Allocator, target_path: []const u8) !void {
        const path_z = try allocator.dupeZ(u8, target_path);
        defer allocator.free(path_z);

        const fp = c.fopen(path_z, "wb") orelse return error.CannotCreateFile;
        defer _ = c.fclose(fp);

        if (self.data.len > 0) {
            const written = c.fwrite(self.data.ptr, 1, self.data.len, fp);
            if (written < self.data.len) return error.WriteFailed;
        }
    }
};

/// Holds all parsed form fields and file attachments from a multipart/form-data request.
pub const FormData = struct {
    allocator: std.mem.Allocator,
    parts: std.ArrayList(MultipartPart),

    pub fn init(allocator: std.mem.Allocator) FormData {
        return .{
            .allocator = allocator,
            .parts = .empty,
        };
    }

    pub fn deinit(self: *FormData) void {
        for (self.parts.items) |p| {
            self.allocator.free(p.name);
            if (p.filename) |f| self.allocator.free(f);
            if (p.content_type) |ct| self.allocator.free(ct);
            self.allocator.free(p.data);
        }
        self.parts.deinit(self.allocator);
    }

    /// Retrieves the text value of a regular form field by name.
    pub fn get(self: *const FormData, name: []const u8) ?[]const u8 {
        for (self.parts.items) |p| {
            if (std.mem.eql(u8, p.name, name) and !p.isFile()) {
                return p.data;
            }
        }
        return null;
    }

    /// Retrieves an uploaded file part by its form field name.
    pub fn getFile(self: *const FormData, name: []const u8) ?MultipartPart {
        for (self.parts.items) |p| {
            if (std.mem.eql(u8, p.name, name) and p.isFile()) {
                return p;
            }
        }
        return null;
    }
};

/// Extracts the boundary parameter from a Content-Type header string
/// e.g. "multipart/form-data; boundary=----WebKitFormBoundaryXYZ" -> "----WebKitFormBoundaryXYZ"
pub fn extractBoundary(content_type: []const u8) ?[]const u8 {
    const needle = "boundary=";
    const idx = std.mem.indexOf(u8, content_type, needle) orelse return null;
    var b = content_type[idx + needle.len ..];
    if (b.len >= 2 and b[0] == '"' and b[b.len - 1] == '"') {
        b = b[1 .. b.len - 1];
    }
    return std.mem.trim(u8, b, " \t\r\n");
}

/// Parses a multipart/form-data raw HTTP body using the given boundary string.
pub fn parse(allocator: std.mem.Allocator, body: []const u8, boundary: []const u8) !FormData {
    var form = FormData.init(allocator);
    errdefer form.deinit();

    // Construct delimiter "--{boundary}"
    const delimiter = try std.fmt.allocPrint(allocator, "--{s}", .{boundary});
    defer allocator.free(delimiter);

    var iter = std.mem.splitSequence(u8, body, delimiter);
    while (iter.next()) |chunk| {
        const trimmed = std.mem.trim(u8, chunk, " \r\n");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "--")) continue;

        // Split headers and body at "\r\n\r\n" or "\n\n"
        var header_end: usize = 0;
        var body_start: usize = 0;
        if (std.mem.indexOf(u8, chunk, "\r\n\r\n")) |idx| {
            header_end = idx;
            body_start = idx + 4;
        } else if (std.mem.indexOf(u8, chunk, "\n\n")) |idx| {
            header_end = idx;
            body_start = idx + 2;
        } else {
            continue;
        }

        const raw_headers = chunk[0..header_end];
        var raw_data = chunk[body_start..];
        // Strip trailing \r\n before next boundary
        if (std.mem.endsWith(u8, raw_data, "\r\n")) {
            raw_data = raw_data[0 .. raw_data.len - 2];
        } else if (std.mem.endsWith(u8, raw_data, "\n")) {
            raw_data = raw_data[0 .. raw_data.len - 1];
        }

        var part_name: ?[]const u8 = null;
        var part_filename: ?[]const u8 = null;
        var part_content_type: ?[]const u8 = null;

        var header_iter = std.mem.splitSequence(u8, raw_headers, "\n");
        while (header_iter.next()) |line| {
            const hline = std.mem.trim(u8, line, " \r");
            if (hline.len == 0) continue;

            if (std.mem.indexOfScalar(u8, hline, ':')) |colon_idx| {
                const hname = std.mem.trim(u8, hline[0..colon_idx], " ");
                const hval = std.mem.trim(u8, hline[colon_idx + 1 ..], " ");

                if (std.ascii.eqlIgnoreCase(hname, "content-disposition")) {
                    // Extract name="..."
                    if (std.mem.indexOf(u8, hval, "name=\"")) |n_idx| {
                        const start = n_idx + 6;
                        if (std.mem.indexOfScalar(u8, hval[start..], '"')) |end_rel| {
                            part_name = hval[start .. start + end_rel];
                        }
                    }
                    // Extract filename="..."
                    if (std.mem.indexOf(u8, hval, "filename=\"")) |f_idx| {
                        const start = f_idx + 10;
                        if (std.mem.indexOfScalar(u8, hval[start..], '"')) |end_rel| {
                            part_filename = hval[start .. start + end_rel];
                        }
                    }
                } else if (std.ascii.eqlIgnoreCase(hname, "content-type")) {
                    part_content_type = hval;
                }
            }
        }

        const name_val = part_name orelse continue;

        const name_dup = try allocator.dupe(u8, name_val);
        errdefer allocator.free(name_dup);

        const filename_dup = if (part_filename) |f| try allocator.dupe(u8, f) else null;
        errdefer if (filename_dup) |f| allocator.free(f);

        const ct_dup = if (part_content_type) |ct| try allocator.dupe(u8, ct) else null;
        errdefer if (ct_dup) |ct| allocator.free(ct);

        const data_dup = try allocator.dupe(u8, raw_data);
        errdefer allocator.free(data_dup);

        try form.parts.append(allocator, .{
            .name = name_dup,
            .filename = filename_dup,
            .content_type = ct_dup,
            .data = data_dup,
        });
    }

    return form;
}
