const std = @import("std");
const builtin = @import("builtin");

/// Returns the current monotonic time in nanoseconds.
pub fn getMonotonicNanos() i128 {
    if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
        return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
    } else {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
    }
}

/// Returns current Unix time in seconds.
pub fn now() i64 {
    if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);
        return @as(i64, @intCast(ts.sec));
    } else {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ts);
        return @as(i64, @intCast(ts.sec));
    }
}

/// Returns current Unix time in milliseconds.
pub fn milliTimestamp() i64 {
    if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);
        return @as(i64, @intCast(ts.sec)) * 1000 + @as(i64, @intCast(@divTrunc(ts.nsec, 1_000_000)));
    } else {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ts);
        return @as(i64, @intCast(ts.sec)) * 1000 + @as(i64, @intCast(@divTrunc(ts.nsec, 1_000_000)));
    }
}

/// Returns current Unix time in nanoseconds.
pub fn nanoTimestamp() i128 {
    if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);
        return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
    } else {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ts);
        return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
    }
}

/// Represents a calendar date and time in UTC.
pub const DateTime = struct {
    year: u16,
    month: u8, // 1-12
    day: u8, // 1-31
    hour: u8, // 0-23
    minute: u8, // 0-59
    second: u8, // 0-59
    weekday: u8, // 0 = Sunday, 1 = Monday, ..., 6 = Saturday

    /// Converts Unix epoch seconds into a DateTime structure.
    pub fn fromEpoch(epoch_seconds: i64) DateTime {
        const secs: u64 = if (epoch_seconds >= 0) @intCast(epoch_seconds) else 0;
        const epoch_sec = std.time.epoch.EpochSeconds{ .secs = secs };
        const epoch_day = epoch_sec.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch_sec.getDaySeconds();

        // Jan 1 1970 was a Thursday (index 4 where Sun=0, Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6)
        const weekday = @as(u8, @intCast(@mod(epoch_day.day + 4, 7)));

        return .{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
            .hour = day_seconds.getHoursIntoDay(),
            .minute = day_seconds.getMinutesIntoHour(),
            .second = day_seconds.getSecondsIntoMinute(),
            .weekday = weekday,
        };
    }

    /// Returns current UTC DateTime.
    pub fn nowUtc() DateTime {
        return fromEpoch(now());
    }

    /// Formats as ISO-8601 / RFC 3339 UTC string: e.g. `2026-10-01T20:44:26Z`.
    pub fn toIso8601(self: DateTime, buf: *[32]u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            self.year, self.month, self.day, self.hour, self.minute, self.second,
        }) catch "1970-01-01T00:00:00Z";
    }

    /// Formats as HTTP-date (RFC 7231 / RFC 1123): e.g. `Thu, 01 Oct 2026 20:44:26 GMT`.
    pub fn toHttpDate(self: DateTime, buf: *[32]u8) []const u8 {
        const days = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
        const months = [_][]const u8{ "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        const day_name = if (self.weekday < 7) days[self.weekday] else "Thu";
        const month_name = if (self.month >= 1 and self.month <= 12) months[self.month] else "Jan";

        return std.fmt.bufPrint(buf, "{s}, {d:0>2} {s} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
            day_name, self.day, month_name, self.year, self.hour, self.minute, self.second,
        }) catch "Thu, 01 Jan 1970 00:00:00 GMT";
    }

    /// Formats date and time: e.g. `2026-10-01 20:44:26`.
    pub fn toStandard(self: DateTime, buf: *[32]u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            self.year, self.month, self.day, self.hour, self.minute, self.second,
        }) catch "1970-01-01 00:00:00";
    }

    /// Formats date only: e.g. `2026-10-01`.
    pub fn toDateString(self: DateTime, buf: *[16]u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            self.year, self.month, self.day,
        }) catch "1970-01-01";
    }

    /// Formats time only: e.g. `20:44:26`.
    pub fn toTimeString(self: DateTime, buf: *[16]u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.hour, self.minute, self.second,
        }) catch "00:00:00";
    }
};

/// Returns current UTC time formatted as ISO-8601 (e.g. `2026-10-01T20:44:26Z`).
pub fn iso8601(buf: *[32]u8) []const u8 {
    return DateTime.nowUtc().toIso8601(buf);
}

/// Returns current UTC time formatted as HTTP Date (e.g. `Thu, 01 Oct 2026 20:44:26 GMT`).
pub fn httpDate(buf: *[32]u8) []const u8 {
    return DateTime.nowUtc().toHttpDate(buf);
}

/// Returns current UTC date formatted as `YYYY-MM-DD`.
pub fn date(buf: *[16]u8) []const u8 {
    return DateTime.nowUtc().toDateString(buf);
}

/// Returns current UTC time formatted as `HH:MM:SS`.
pub fn timeOfDay(buf: *[16]u8) []const u8 {
    return DateTime.nowUtc().toTimeString(buf);
}

/// Parses an ISO-8601 date string (e.g. `2026-10-01T20:44:26Z` or `2026-10-01T20:44:26`).
pub fn parseIso8601(str: []const u8) ?DateTime {
    if (str.len < 19) return null;
    if (str[4] != '-' or str[7] != '-' or (str[10] != 'T' and str[10] != ' ') or str[13] != ':' or str[16] != ':') {
        return null;
    }
    const year = std.fmt.parseInt(u16, str[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, str[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, str[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, str[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, str[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, str[17..19], 10) catch return null;

    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .weekday = 0,
    };
}
