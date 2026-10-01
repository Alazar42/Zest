const std = @import("std");

pub const ValidationError = struct {
    field: []const u8,
    message: []const u8,
};

/// Collects field-level validation errors to return in a structured HTTP 422 response.
pub const ValidationErrors = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ValidationError),

    pub fn init(allocator: std.mem.Allocator) ValidationErrors {
        return .{
            .allocator = allocator,
            .errors = .empty,
        };
    }

    pub fn deinit(self: *ValidationErrors) void {
        for (self.errors.items) |e| {
            self.allocator.free(e.field);
            self.allocator.free(e.message);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn add(self: *ValidationErrors, field: []const u8, message: []const u8) void {
        const f_dup = self.allocator.dupe(u8, field) catch return;
        const m_dup = self.allocator.dupe(u8, message) catch {
            self.allocator.free(f_dup);
            return;
        };
        self.errors.append(self.allocator, .{ .field = f_dup, .message = m_dup }) catch {
            self.allocator.free(f_dup);
            self.allocator.free(m_dup);
        };
    }

    pub fn hasErrors(self: *const ValidationErrors) bool {
        return self.errors.items.len > 0;
    }

    /// Serializes errors into FastAPI / Pydantic style JSON:
    /// `{"detail": [{"field": "email", "message": "Invalid email format"}]}`
    pub fn toJson(self: *const ValidationErrors, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\"detail\":[");
        for (self.errors.items, 0..) |err_item, i| {
            if (i > 0) try buf.append(allocator, ',');
            const item_str = try std.fmt.allocPrint(allocator, "{{\"field\":\"{s}\",\"message\":\"{s}\"}}", .{ err_item.field, err_item.message });
            defer allocator.free(item_str);
            try buf.appendSlice(allocator, item_str);
        }
        try buf.appendSlice(allocator, "]}");
        return buf.toOwnedSlice(allocator);
    }
};

/// Standard validation helpers for models and DTOs.
pub const validator = struct {
    pub fn requireNotEmpty(errs: *ValidationErrors, field: []const u8, val: []const u8) void {
        const trimmed = std.mem.trim(u8, val, " \t\r\n");
        if (trimmed.len == 0) {
            errs.add(field, "Field cannot be empty");
        }
    }

    pub fn requireMinLength(errs: *ValidationErrors, field: []const u8, val: []const u8, min_len: usize) void {
        if (val.len < min_len) {
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Length must be at least {d} characters", .{min_len}) catch "Length is too short";
            errs.add(field, msg);
        }
    }

    pub fn requireMaxLength(errs: *ValidationErrors, field: []const u8, val: []const u8, max_len: usize) void {
        if (val.len > max_len) {
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Length must be at most {d} characters", .{max_len}) catch "Length is too long";
            errs.add(field, msg);
        }
    }

    pub fn requireEmail(errs: *ValidationErrors, field: []const u8, val: []const u8) void {
        if (val.len < 3 or std.mem.indexOfScalar(u8, val, '@') == null or std.mem.indexOfScalar(u8, val, '.') == null) {
            errs.add(field, "Invalid email address format");
        }
    }

    pub fn requireMin(errs: *ValidationErrors, field: []const u8, val: anytype, min_val: anytype) void {
        if (val < min_val) {
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Value must be at least {any}", .{min_val}) catch "Value is below minimum";
            errs.add(field, msg);
        }
    }

    pub fn requireMax(errs: *ValidationErrors, field: []const u8, val: anytype, max_val: anytype) void {
        if (val > max_val) {
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Value must be at most {any}", .{max_val}) catch "Value exceeds maximum";
            errs.add(field, msg);
        }
    }

    pub fn requireRange(errs: *ValidationErrors, field: []const u8, val: anytype, min_val: anytype, max_val: anytype) void {
        if (val < min_val or val > max_val) {
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Value must be between {any} and {any}", .{ min_val, max_val }) catch "Value is out of range";
            errs.add(field, msg);
        }
    }
};
