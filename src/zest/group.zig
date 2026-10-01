const std = @import("std");
const App = @import("app.zig");
const Route = @import("route.zig");
const middleware = @import("middleware.zig");
const MiddlewareFn = middleware.MiddlewareFn;

prefix: []const u8,
app: *App,
middlewares: std.ArrayList(MiddlewareFn),

const Self = @This();

/// Initializes a new route Group attached to the given App.
pub fn init(app: *App, prefix: []const u8) Self {
    return .{
        .prefix = prefix,
        .app = app,
        .middlewares = .empty,
    };
}

/// Frees memory allocated by this group.
pub fn deinit(self: *Self) void {
    self.middlewares.deinit(self.app.allocator);
}

/// Adds a middleware to this group and all its sub-routes and sub-groups.
pub fn use(self: *Self, mw: MiddlewareFn) !void {
    try self.middlewares.append(self.app.allocator, mw);
}

/// Creates a nested sub-group under this group (e.g. `/api` -> `/v1`).
pub fn group(self: *Self, sub_prefix: []const u8) !Self {
    const combined = try std.fmt.allocPrint(self.app.allocator, "{s}{s}", .{ self.prefix, sub_prefix });
    var sub = Self.init(self.app, combined);
    for (self.middlewares.items) |mw| {
        try sub.middlewares.append(self.app.allocator, mw);
    }
    return sub;
}

/// Registers a route on this group with combined path and group middlewares.
pub fn add(self: *Self, method: std.http.Method, sub_path: []const u8, comptime handler: anytype) !void {
    const full_path = try std.fmt.allocPrint(self.app.allocator, "{s}{s}", .{ self.prefix, sub_path });
    const mw_slice = try self.app.allocator.dupe(MiddlewareFn, self.middlewares.items);
    try self.app.router.addWithMiddlewares(method, full_path, Route.wrap(handler), mw_slice);
}

pub fn get(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.GET, path, handler);
}

pub fn post(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.POST, path, handler);
}

pub fn put(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.PUT, path, handler);
}

pub fn delete(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.DELETE, path, handler);
}

pub fn patch(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.PATCH, path, handler);
}
