const std = @import("std");
const zest = @import("zest");
const database = @import("database.zig");
const Product = @import("models/product.zig").Product;
const products_routes = @import("routes/products.zig");

fn welcome(res: *zest.Response) !void {
    try res.json(.{ .message = "Welcome to Zest API! Visit /docs for Swagger UI." });
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // 1. Load .env configuration via zenv
    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:products.db");
    const port = zest.zenv.getInt("PORT", u16) orelse 8000;

    // 2. Initialize Database and seed sample products
    try database.init(gpa, db_url);
    defer database.deinit();

    try Product.model.save(&database.db, gpa, &.{ .id = &zest.zuuid.generate(), .name = "Apple iPhone", .price = 999.99 });
    try Product.model.save(&database.db, gpa, &.{ .id = &zest.zuuid.generate(), .name = "MacBook Pro", .price = 1999.99 });

    // 3. Initialize Zest Application
    var app = zest.init("127.0.0.1", port);
    defer app.deinit();

    // 4. Middlewares & OpenAPI Swagger UI
    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));
    app.enableDocs();
    try app.registerModel(Product);

    // 5. Mount Root Route & Sub-Router Group
    try app.get("/", welcome);

    var api = app.group("/api/v1");
    var products_group = try api.group("/products");
    try products_routes.register(&products_group);

    // 6. Start Server
    try app.serve();
}
