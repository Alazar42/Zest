const std = @import("std");
const Db = @import("db.zig");

const Mutex = struct {
    state: std.atomic.Mutex = .unlocked,

    pub fn lock(self: *@This()) void {
        while (!self.state.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *@This()) void {
        self.state.unlock();
    }
};

/// Thread-safe database connection pool for high-concurrency environments.
pub const DbPool = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    max_size: usize,
    mutex: Mutex = .{},
    idle_connections: std.ArrayList(Db),
    active_count: usize = 0,

    const Self = @This();

    /// Initializes a connection pool with the specified database URL and pool capacity.
    pub fn init(allocator: std.mem.Allocator, url: []const u8, max_size: usize) !Self {
        const url_dup = try allocator.dupe(u8, url);
        return .{
            .allocator = allocator,
            .url = url_dup,
            .max_size = if (max_size == 0) 10 else max_size,
            .idle_connections = .empty,
            .active_count = 0,
        };
    }

    /// Acquires a connection from the pool, or creates a new one if below max_size.
    pub fn acquire(self: *Self) !Db {
        self.mutex.lock();
        if (self.idle_connections.items.len > 0) {
            const conn = self.idle_connections.pop().?;
            self.active_count += 1;
            self.mutex.unlock();
            return conn;
        }

        if (self.active_count < self.max_size) {
            self.active_count += 1;
            self.mutex.unlock();
            return Db.connect(self.allocator, self.url) catch |err| {
                self.mutex.lock();
                self.active_count -= 1;
                self.mutex.unlock();
                return err;
            };
        }

        self.mutex.unlock();
        // Wait or yield if at max capacity, then create temporary fallback connection
        return Db.connect(self.allocator, self.url);
    }

    /// Releases a connection back into the idle pool.
    pub fn release(self: *Self, conn: Db) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.idle_connections.items.len < self.max_size) {
            self.idle_connections.append(self.allocator, conn) catch {
                var c = conn;
                c.deinit();
            };
        } else {
            var c = conn;
            c.deinit();
        }

        if (self.active_count > 0) {
            self.active_count -= 1;
        }
    }

    /// Returns the number of currently idle connections.
    pub fn idleCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.idle_connections.items.len;
    }

    /// Closes all idle connections and frees pool resources.
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.idle_connections.items) |*conn| {
            conn.deinit();
        }
        self.idle_connections.deinit(self.allocator);
        self.allocator.free(self.url);
    }
};
