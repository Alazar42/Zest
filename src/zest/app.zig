const std = @import("std");
const net = std.Io.net;

pub const Request = @import("request.zig");
pub const Response = @import("response.zig");
pub const Router = @import("router.zig");
pub const Route = @import("route.zig");
pub const Param = @import("param.zig");
pub const Static = @import("static.zig");
pub const middleware = @import("middleware.zig");
pub const Model = @import("model.zig").Model;
pub const Group = @import("group.zig");
pub const Cookie = @import("cookie.zig");
pub const jwt = @import("jwt.zig");
pub const Db = @import("db.zig");
pub const openapi = @import("openapi.zig");
pub const HandlerFn = Route.HandlerFn;
pub const MiddlewareFn = middleware.MiddlewareFn;
pub const time = @import("time.zig");

allocator: std.mem.Allocator,
threaded: ?*std.Io.Threaded,
io: std.Io,
host: []const u8,
port: u16,
router: Router,
middlewares: std.ArrayList(MiddlewareFn),
static_routes: std.ArrayList(Static),
should_stop: std.atomic.Value(bool),
server: ?net.Server,
docs_enabled: bool,
docs_path: []const u8,
openapi_path: []const u8,
openapi_spec: openapi,
tls_enabled: bool = false,
cert_path: ?[]const u8 = null,
key_path: ?[]const u8 = null,

const Self = @This();

/// Initializes a new Zest application instance with default Threaded I/O:
/// `var app = zest.init("127.0.0.1", 8000);`
pub fn init(host: []const u8, port: u16) Self {
    const gpa = std.heap.page_allocator;
    const threaded = gpa.create(std.Io.Threaded) catch @panic("Out of memory");
    threaded.* = std.Io.Threaded.init(gpa, .{});
    return initWithIo(gpa, threaded.io(), threaded, host, port);
}

/// Initializes a Zest application with custom allocator and Io instance.
pub fn initWithIo(
    allocator: std.mem.Allocator,
    io: std.Io,
    threaded: ?*std.Io.Threaded,
    host: []const u8,
    port: u16,
) Self {
    return .{
        .allocator = allocator,
        .threaded = threaded,
        .io = io,
        .host = host,
        .port = port,
        .router = Router.init(allocator),
        .middlewares = .empty,
        .static_routes = .empty,
        .should_stop = std.atomic.Value(bool).init(false),
        .server = null,
        .docs_enabled = false,
        .docs_path = "/docs",
        .openapi_path = "/openapi.json",
        .openapi_spec = .{},
        .tls_enabled = false,
        .cert_path = null,
        .key_path = null,
    };
}

/// Frees allocated memory for routes, middlewares, router, and runtime resources.
pub fn deinit(self: *Self) void {
    self.router.deinit();
    self.middlewares.deinit(self.allocator);
    self.static_routes.deinit(self.allocator);
    self.openapi_spec.deinit(self.allocator);
    if (self.threaded) |t| {
        t.deinit();
        self.allocator.destroy(t);
        self.threaded = null;
    }
}

/// Registers global middleware (e.g. logger, CORS) executed before route matching.
pub fn use(self: *Self, mw: MiddlewareFn) !void {
    try self.middlewares.append(self.allocator, mw);
}

/// Mounts static file serving for files in `dir_path` at `url_prefix`.
pub fn static(self: *Self, url_prefix: []const u8, dir_path: []const u8) !void {
    try self.static_routes.append(self.allocator, .{
        .prefix = url_prefix,
        .dir = dir_path,
    });
}

/// Registers a route for any given HTTP method.
pub fn route(self: *Self, method: std.http.Method, path: []const u8, comptime handler: anytype) !void {
    try self.router.add(method, path, handler);
}

/// Registers a GET route.
pub fn get(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.get(path, handler);
}

/// Registers a POST route.
pub fn post(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.post(path, handler);
}

/// Registers a PUT route.
pub fn put(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.put(path, handler);
}

/// Registers a DELETE route.
pub fn delete(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.delete(path, handler);
}

/// Registers a PATCH route.
pub fn patch(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.patch(path, handler);
}

/// Registers a HEAD route.
pub fn head(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.head(path, handler);
}

/// Registers an OPTIONS route.
pub fn options(self: *Self, path: []const u8, comptime handler: anytype) !void {
    try self.router.options(path, handler);
}

/// Creates a sub-router route group with a common path prefix (e.g. `app.group("/api/v1")`).
pub fn group(self: *Self, prefix: []const u8) Group {
    return Group.init(self, prefix);
}

/// Enables OpenAPI 3.0 specification generation and interactive Swagger UI at `/docs`.
pub fn enableDocs(self: *Self) void {
    self.docs_enabled = true;
}

/// Enables HTTPS/TLS using SSL certificate and private key files.
pub fn enableTls(self: *Self, cert_file: []const u8, key_file: []const u8) void {
    self.tls_enabled = true;
    self.cert_path = cert_file;
    self.key_path = key_file;
}

/// Returns the active URL protocol scheme ("http" or "https").
pub fn scheme(self: *const Self) []const u8 {
    return if (self.tls_enabled or self.port == 443) "https" else "http";
}

/// Enables interactive Swagger UI with custom endpoint paths and metadata.
pub fn enableDocsCustom(self: *Self, docs_path: []const u8, openapi_path: []const u8, title: []const u8, version: []const u8, description: []const u8) void {
    self.docs_enabled = true;
    self.docs_path = docs_path;
    self.openapi_path = openapi_path;
    self.openapi_spec = .{
        .title = title,
        .version = version,
        .description = description,
    };
}

/// Registers a model struct type for OpenAPI schema generation.
/// Inspects struct fields at comptime and registers accurate types (integer, string, number, boolean) under `components.schemas`.
pub fn registerModel(self: *Self, comptime T: type) !void {
    const name = openapi.typeBasename(T);
    const props = comptime openapi.generateModelPropertiesJson(T);
    const required = comptime openapi.generateModelRequiredJson(T);
    try self.openapi_spec.registerSchemaWithRequired(self.allocator, name, props, required);
}

/// Registers a custom named schema with raw JSON properties under `components.schemas`.
pub fn registerSchema(self: *Self, name: []const u8, properties_json: []const u8) !void {
    try self.openapi_spec.registerSchema(self.allocator, name, properties_json);
}

/// Alias for `serve()` (Express / Node.js style).
pub fn listen(self: *Self) !void {
    return self.serve();
}

/// Signals the server loop to gracefully stop.
pub fn stop(self: *Self) void {
    self.should_stop.store(true, .monotonic);
    if (self.server) |*s| {
        s.socket.close(self.io);
    }
}

/// Starts the HTTP server and begins listening for incoming requests.
pub fn serve(self: *Self) !void {
    const address = try net.IpAddress.parse(self.host, self.port);
    var server = try address.listen(self.io, .{ .reuse_address = true });
    self.server = server;
    defer {
        server.deinit(self.io);
        self.server = null;
    }

    const protocol = self.scheme();
    std.log.info("[Zest] Server listening on {s}://{s}:{d}/", .{ protocol, self.host, self.port });

    var io_group: std.Io.Group = .init;
    defer io_group.cancel(self.io);

    while (!self.should_stop.load(.monotonic)) {
        var stream = server.accept(self.io) catch |err| switch (err) {
            error.Canceled => break,
            else => |e| {
                if (self.should_stop.load(.monotonic)) break;
                std.log.err("failed to accept connection: {t}", .{e});
                continue;
            },
        };

        io_group.concurrent(self.io, handleConnectionTask, .{ self, stream }) catch |err| {
            std.log.err("unable to spawn connection worker: {t}", .{err});
            stream.close(self.io);
            continue;
        };
    }
}

fn handleConnectionTask(self: *Self, stream: net.Stream) void {
    defer {
        var copy = stream;
        copy.close(self.io);
    }

    var recv_buffer: [8192]u8 = undefined;
    var send_buffer: [8192]u8 = undefined;
    var connection_reader = stream.reader(self.io, &recv_buffer);
    var connection_writer = stream.writer(self.io, &send_buffer);
    var http_server = std.http.Server.init(&connection_reader.interface, &connection_writer.interface);

    while (true) {
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.log.debug("HTTP request error: {t}", .{err});
                return;
            },
        };

        // In HTTP, if a POST/PUT/PATCH request has no Content-Length and no Transfer-Encoding,
        // normalize content_length to 0 so standard library keep_alive discard body does not assert.
        if (request.head.method.requestHasBody() and request.head.transfer_encoding == .none and request.head.content_length == null) {
            request.head.content_length = 0;
        }

        self.dispatchRequest(&request);

        if (!request.head.keep_alive) {
            return;
        }
    }
}

fn dispatchRequest(self: *Self, request: *std.http.Server.Request) void {
    var req = Request.init(request, self.allocator, self.io);
    defer req.deinit();
    var res: Response = .{
        .server_request = request,
        .request = &req,
        .headers = .empty,
        .status_code = .ok,
        .log_enabled = false,
    };
    defer res.deinit();
    defer {
        if (res.log_enabled) {
            middleware.logResponse(&req, &res);
        }
        // Run queued background tasks after response is sent
        req.background_tasks.runAll();
    }
    req.response = &res;

    self.handleInternal(&req, &res, request, req.path()) catch |err| {
        res.status_code = .internal_server_error;
        std.log.err("Error handling request '{s}': {t}", .{ req.target(), err });
        if (!res.sent) {
            res.sendWithHeaders("500 Internal Server Error\n", .internal_server_error, "text/plain; charset=utf-8") catch {};
        }
    };
}

fn handleInternal(self: *Self, req: *Request, res: *Response, request: *std.http.Server.Request, path_only: []const u8) !void {
    // 1. Run global middleware chain
    for (self.middlewares.items) |mw| {
        const proceed = try mw(req, res);
        if (!proceed) {
            return; // Middleware handled the request
        }
    }

    // 2. Check static file routes
    for (self.static_routes.items) |s| {
        if (try s.serve(self.io, self.allocator, req, res)) {
            return; // Static file served
        }
    }

    // 3. Check OpenAPI documentation endpoints
    if (self.docs_enabled) {
        if (std.mem.eql(u8, path_only, self.docs_path)) {
            return try openapi.serveDocsHtml(res, self.openapi_path);
        }
        if (std.mem.eql(u8, path_only, self.openapi_path)) {
            const spec_json = try self.openapi_spec.generateJson(self.allocator, self.router.routes.items);
            defer self.allocator.free(spec_json);
            return try res.json(spec_json);
        }
    }

    // 4. Match route and extract dynamic path parameters
    if (self.router.find(request.head.method, path_only, &req.params, &req.params_len)) |matched_route| {
        // Run route/group specific middlewares
        for (matched_route.middlewares) |mw| {
            const proceed = try mw(req, res);
            if (!proceed) {
                return;
            }
        }
        return try matched_route.handler(req, res);
    }

    // Route not found -> 404
    if (!res.sent) {
        res.status_code = .not_found;
        try res.sendWithHeaders("404 Not Found\n", .not_found, "text/plain; charset=utf-8");
    }
}
