const std = @import("std");
const zest = @import("zest");
const database = @import("../database.zig");
const Item = @import("../models/item.zig");

/// GET /items or /api/v1/items: Retrieves all items, optionally filtered with ?search=...&limit=...
pub fn getAll(req: *zest.Request, res: *zest.Response) !void {
    var q = Item.model.query(&database.db, req.allocator);
    if (req.queryParam("search")) |s| {
        _ = q.where("name", .contains, s);
    }
    if (req.queryParam("limit")) |l| {
        if (std.fmt.parseInt(usize, l, 10) catch null) |lim| {
            _ = q.limit(lim);
        }
    }

    const items = try q.execJson();
    defer {
        for (items) |doc| req.allocator.free(doc);
        req.allocator.free(items);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(req.allocator);
    try out.append(req.allocator, '[');
    for (items, 0..) |doc, i| {
        if (i > 0) try out.append(req.allocator, ',');
        try out.appendSlice(req.allocator, doc);
    }
    try out.append(req.allocator, ']');
    try res.json(out.items);
}

/// GET /items/:id: Retrieves a single item by its ID.
pub fn getById(req: *zest.Request, res: *zest.Response) !void {
    const item_id = req.paramInt("id", u32) orelse {
        try res.status(.bad_request, "{\"error\": \"Invalid item ID\"}");
        return;
    };

    var found = try Item.model.find(&database.db, req.allocator, item_id);
    if (found) |*p| {
        defer p.deinit();
        try res.jsonValue(p.value);
    } else {
        try res.status(.not_found, "{\"error\": \"Item not found\"}");
    }
}

/// POST /items: Creates a new item with automated FastAPI-style schema validation.
pub fn create(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Item, res)) orelse return;
    defer parsed.deinit();

    try Item.model.save(&database.db, req.allocator, &parsed.value);
    try res.jsonValue(parsed.value);
}

/// DELETE /items/:id: Removes an item by its ID from the database.
pub fn deleteItem(req: *zest.Request, res: *zest.Response) !void {
    const item_id = req.paramInt("id", u32) orelse {
        try res.status(.bad_request, "{\"error\": \"Invalid item ID\"}");
        return;
    };

    if (Item.model.delete(&database.db, item_id)) {
        try res.json("{\"message\": \"Item deleted successfully\"}");
    } else {
        try res.status(.not_found, "{\"error\": \"Item not found\"}");
    }
}
