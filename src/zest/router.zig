const std = @import("std");
const Route = @import("route.zig");
const Param = @import("param.zig");

pub const HandlerFn = Route.HandlerFn;

allocator: std.mem.Allocator,
routes: std.ArrayList(Route),

const Self = @This();

/// Initializes a new Router.
pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .routes = .empty,
    };
}

/// Frees allocated memory for routes.
pub fn deinit(self: *Self) void {
    self.routes.deinit(self.allocator);
}

/// Registers a route for any given HTTP method with automatic handler signature wrapping.
pub fn add(self: *Self, method: std.http.Method, path: []const u8, comptime handler: anytype) !void {
    try self.routes.append(self.allocator, .{
        .method = method,
        .path = path,
        .handler = Route.wrap(handler),
        .middlewares = &.{},
    });
}

/// Registers a route with pre-configured middlewares and wrapped handler.
pub fn addWithMiddlewares(self: *Self, method: std.http.Method, path: []const u8, handler: HandlerFn, middlewares: []const Route.MiddlewareFn) !void {
    try self.routes.append(self.allocator, .{
        .method = method,
        .path = path,
        .handler = handler,
        .middlewares = middlewares,
    });
}

/// Registers a GET route.
pub fn get(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.GET, path, handler);
}

/// Registers a POST route.
pub fn post(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.POST, path, handler);
}

/// Registers a PUT route.
pub fn put(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.PUT, path, handler);
}

/// Registers a DELETE route.
pub fn delete(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.DELETE, path, handler);
}

/// Registers a PATCH route.
pub fn patch(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.PATCH, path, handler);
}

/// Registers a HEAD route.
pub fn head(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.HEAD, path, handler);
}

/// Registers an OPTIONS route.
pub fn options(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.add(.OPTIONS, path, handler);
}

/// Finds the registered handler for the given method and path, extracting path parameters.
/// Supports both exact routes and dynamic routes (e.g. `/items/:id`).
pub fn find(
    self: *const Self,
    method: std.http.Method,
    req_path: []const u8,
    out_params: *[16]Param,
    out_params_len: *usize,
) ?Route {
    const clean_req_path = if (req_path.len > 1 and req_path[req_path.len - 1] == '/')
        req_path[0 .. req_path.len - 1]
    else
        req_path;

    // 1. First check for matching method
    for (self.routes.items) |r| {
        if (r.method == method) {
            const clean_r_path = if (r.path.len > 1 and r.path[r.path.len - 1] == '/')
                r.path[0 .. r.path.len - 1]
            else
                r.path;
            if (matchRoute(clean_r_path, clean_req_path, out_params, out_params_len)) {
                return r;
            }
        }
    }

    // 2. If HEAD request, check GET routes as fallback
    if (method == .HEAD) {
        for (self.routes.items) |r| {
            if (r.method == .GET) {
                const clean_r_path = if (r.path.len > 1 and r.path[r.path.len - 1] == '/')
                    r.path[0 .. r.path.len - 1]
                else
                    r.path;
                if (matchRoute(clean_r_path, clean_req_path, out_params, out_params_len)) {
                    return r;
                }
            }
        }
    }

    return null;
}

fn matchRoute(
    route_path: []const u8,
    req_path: []const u8,
    out_params: *[16]Param,
    out_params_len: *usize,
) bool {
    // Fast path: exact match
    if (std.mem.eql(u8, route_path, req_path)) {
        out_params_len.* = 0;
        return true;
    }

    // Dynamic path matching: requires ':'
    if (std.mem.indexOfScalar(u8, route_path, ':') == null) {
        return false;
    }

    var r_iter = std.mem.splitScalar(u8, route_path, '/');
    var q_iter = std.mem.splitScalar(u8, req_path, '/');
    var p_count: usize = 0;

    while (true) {
        const r_seg = r_iter.next();
        const q_seg = q_iter.next();

        if (r_seg == null and q_seg == null) {
            out_params_len.* = p_count;
            return true;
        }

        if (r_seg == null or q_seg == null) {
            return false;
        }

        const r_val = r_seg.?;
        const q_val = q_seg.?;

        if (r_val.len > 0 and r_val[0] == ':') {
            const param_name = r_val[1..];
            if (p_count < 16) {
                out_params[p_count] = .{
                    .name = param_name,
                    .value = q_val,
                };
                p_count += 1;
            }
        } else if (!std.mem.eql(u8, r_val, q_val)) {
            return false;
        }
    }
}
