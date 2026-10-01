const std = @import("std");

pub const TaskFn = *const fn (ctx: ?*anyopaque) void;

pub const BackgroundTask = struct {
    func: TaskFn,
    ctx: ?*anyopaque = null,
    cleanup: ?*const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator) void = null,
};

/// Collects and executes asynchronous tasks outside the client request/response path.
pub const BackgroundTasks = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(BackgroundTask),

    pub fn init(allocator: std.mem.Allocator) BackgroundTasks {
        return .{
            .allocator = allocator,
            .tasks = .empty,
        };
    }

    pub fn deinit(self: *BackgroundTasks) void {
        for (self.tasks.items) |t| {
            if (t.cleanup) |c| {
                c(t.ctx, self.allocator);
            }
        }
        self.tasks.deinit(self.allocator);
    }

    /// Adds a background task to be executed after the HTTP response has finished.
    pub fn add(self: *BackgroundTasks, func: TaskFn, ctx: ?*anyopaque) !void {
        try self.tasks.append(self.allocator, .{
            .func = func,
            .ctx = ctx,
            .cleanup = null,
        });
    }

    /// Adds a background task with a custom context cleanup function.
    pub fn addWithCleanup(
        self: *BackgroundTasks,
        func: TaskFn,
        ctx: ?*anyopaque,
        cleanup: *const fn (?*anyopaque, std.mem.Allocator) void,
    ) !void {
        try self.tasks.append(self.allocator, .{
            .func = func,
            .ctx = ctx,
            .cleanup = cleanup,
        });
    }

    /// Runs all scheduled background tasks sequentially and cleans up resources.
    pub fn runAll(self: *BackgroundTasks) void {
        for (self.tasks.items) |t| {
            t.func(t.ctx);
            if (t.cleanup) |c| {
                c(t.ctx, self.allocator);
            }
        }
        self.tasks.clearRetainingCapacity();
    }

    /// Returns the number of queued background tasks.
    pub fn count(self: *const BackgroundTasks) usize {
        return self.tasks.items.len;
    }
};
