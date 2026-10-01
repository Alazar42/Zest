const std = @import("std");
const builtin = @import("builtin");

/// Returns the current monotonic time in nanoseconds.
pub fn getMonotonicNanos() i128 {
    if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
        return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
    } else {
        return 0;
    }
}
