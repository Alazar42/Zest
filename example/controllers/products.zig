const std = @import("std");
const zest = @import("zest");
const database = @import("../database.zig");
const Product = @import("../models/product.zig").Product;

/// GET /api/v1/products - Filter and list products
pub fn getAll(req: *zest.Request, res: *zest.Response) !void {
    var q = Product.model.query(&database.db, req.allocator);
    if (req.queryParam("search")) |s| {
        _ = q.where("name", .contains, s);
    }
    const products = try q.exec();
    defer {
        for (products) |*p| p.deinit();
        req.allocator.free(products);
    }
    try res.jsonValue(products);
}

/// GET /api/v1/products/:id - Fetch single product by UUID
pub fn getById(req: *zest.Request, res: *zest.Response) !void {
    const id = req.param("id") orelse {
        try res.status(.bad_request, "{\"error\": \"Missing product ID\"}");
        return;
    };

    var found = try Product.model.find(&database.db, req.allocator, id);
    if (found) |*p| {
        defer p.deinit();
        try res.jsonValue(p.value);
    } else {
        try res.status(.not_found, "{\"error\": \"Product not found\"}");
    }
}

/// POST /api/v1/products - Creates product with auto-generated UUID v4 if not provided
pub fn create(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    var product = parsed.value;
    var uuid_buf: [36]u8 = undefined;
    if (product.id == null or product.id.?.len == 0) {
        product.id = try req.allocator.dupe(u8, zest.uuid.v4(&uuid_buf));
    }

    try Product.model.save(&database.db, req.allocator, &product);
    const body = try std.fmt.allocPrint(req.allocator, "{{\"status\":\"created\",\"id\":\"{s}\"}}", .{product.id.?});
    try res.status(.created, body);
}

/// DELETE /api/v1/products/:id - Delete product by UUID
pub fn deleteProduct(req: *zest.Request, res: *zest.Response) !void {
    const id = req.param("id") orelse {
        try res.status(.bad_request, "{\"error\": \"Missing product ID\"}");
        return;
    };

    if (Product.model.delete(&database.db, id)) {
        try res.json("{\"message\": \"Product deleted successfully\"}");
    } else {
        try res.status(.not_found, "{\"error\": \"Product not found\"}");
    }
}
