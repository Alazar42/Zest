const std = @import("std");
const zest = @import("zest");
const database = @import("database.zig");
const Item = @import("models/item.zig");

// Route Registrars
const items_routes = @import("routes/items.zig");
const auth_routes = @import("routes/auth.zig");

fn readRoot(res: *zest.Response) !void {
    try res.json("{\"message\": \"Welcome to Zest Modular Web Framework! Visit /docs for Swagger UI.\"}");
}

fn handleUpload(req: *zest.Request, res: *zest.Response) !void {
    var form = try req.multipart();
    defer form.deinit();

    const username = form.get("username") orelse "anonymous";
    if (form.getFile("avatar")) |file| {
        try file.saveTo(req.allocator, "example/uploaded_avatar.txt");
    }

    // Schedule background task to execute outside of the HTTP response cycle
    const bgTask = struct {
        fn onComplete(_: ?*anyopaque) void {
            std.log.info("[Zest] Background task completed: processed upload and sent notification", .{});
        }
    }.onComplete;
    try req.addBackgroundTask(bgTask, null);

    var buf: [256]u8 = undefined;
    const response_msg = try std.fmt.bufPrint(&buf, "{{\"status\":\"uploaded\",\"user\":\"{s}\"}}", .{username});
    try res.json(response_msg);
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // 1. Load environment variables via zenv (like python-dotenv)
    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    // 2. Read database URL and server port from environment or defaults
    const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:zest.db");
    const port = zest.zenv.getInt("PORT", u16) orelse 8000;

    // 3. Initialize Database (real SQLite file, Supabase PostgreSQL, or MongoDB) and seed sample records
    try database.init(gpa, db_url);
    defer database.deinit();

    try Item.model.save(&database.db, gpa, &.{ .id = 1, .name = "Apple", .price = 1.99 });
    try Item.model.save(&database.db, gpa, &.{ .id = 2, .name = "Banana", .price = 0.99 });

    // 4. Initialize Zest Application
    var app = zest.init("127.0.0.1", port);
    defer app.deinit();

    // 3. Middlewares
    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));

    // 4. Static Files & Auto OpenAPI / Swagger UI
    try app.static("/public", "./public");
    app.enableDocs();

    // 5. Root Route & Upload Route
    try app.get("/", readRoot);
    try app.post("/upload", handleUpload);

    // 6. Sub-Router Group (/api/v1)
    var api = app.group("/api/v1");

    var items_group = try api.group("/items");
    try items_routes.register(&items_group);

    var auth_group = try api.group("/auth");
    try auth_routes.register(&auth_group);

    // Also mount directly at /items for convenience
    var root_items = app.group("/items");
    try items_routes.register(&root_items);

    // 7. Start Server
    try app.serve();
}
