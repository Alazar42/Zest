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
    // res.jsonValue automatically serializes Parsed model slices cleanly
    try res.jsonValue(products);
}

/// GET /api/v1/products/:id - Fetch single product by ID
pub fn getById(req: *zest.Request, res: *zest.Response) !void {
    const id = req.paramInt("id", u32) orelse {
        try res.status(.bad_request, "{\"error\": \"Invalid product ID\"}");
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

/// POST /api/v1/products - Creates product with automatic HTTP 422 validation and auto-increment ID
pub fn create(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    var product = parsed.value;
    if (product.id == null or product.id.? == 0) {
        var max_id: u32 = 0;
        var q = Product.model.query(&database.db, req.allocator);
        const existing = try q.exec();
        defer {
            for (existing) |*p| p.deinit();
            req.allocator.free(existing);
        }
        for (existing) |p| {
            if (p.value.id) |existing_id| {
                if (existing_id > max_id) max_id = existing_id;
            }
        }
        product.id = max_id + 1;
    }

    try Product.model.save(&database.db, req.allocator, &product);
    try res.status(.created, "{\"status\":\"created\"}");
}

/// DELETE /api/v1/products/:id - Delete product by ID
pub fn deleteProduct(req: *zest.Request, res: *zest.Response) !void {
    const id = req.paramInt("id", u32) orelse {
        try res.status(.bad_request, "{\"error\": \"Invalid product ID\"}");
        return;
    };

    if (Product.model.delete(&database.db, id)) {
        try res.json("{\"message\": \"Product deleted successfully\"}");
    } else {
        try res.status(.not_found, "{\"error\": \"Product not found\"}");
    }
}
