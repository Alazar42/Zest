const std = @import("std");
const Route = @import("route.zig");
const Response = @import("response.zig");

title: []const u8 = "Zest API",
version: []const u8 = "1.0.0",
description: []const u8 = "Fast, modern web API powered by Zest and Zig",

const Self = @This();

/// Converts a Zest path with `:param` (e.g. `/items/:id`) into a normalized OpenAPI path template (e.g. `/items/{id}`).
/// Strips duplicate trailing slashes (e.g. `/items/` -> `/items`, except for root `/`).
pub fn toOpenApiPath(allocator: std.mem.Allocator, raw_path: []const u8) ![]u8 {
    var path = raw_path;
    while (path.len > 1 and path[path.len - 1] == '/') {
        path = path[0 .. path.len - 1];
    }
    if (path.len == 0) path = "/";

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var iter = std.mem.splitScalar(u8, path, '/');
    var is_first = true;
    while (iter.next()) |segment| {
        if (is_first) {
            is_first = false;
        } else {
            try out.append(allocator, '/');
        }
        if (segment.len > 0 and segment[0] == ':') {
            try out.append(allocator, '{');
            try out.appendSlice(allocator, segment[1..]);
            try out.append(allocator, '}');
        } else {
            try out.appendSlice(allocator, segment);
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Extracts a clean, capitalized domain resource tag from a path (e.g. `/api/v1/products/:id` -> `Products`).
pub fn extractTag(buf: *[64]u8, path: []const u8) []const u8 {
    var seg_iter = std.mem.splitScalar(u8, path, '/');
    while (seg_iter.next()) |s| {
        if (s.len == 0) continue;
        if (s[0] == ':') continue;
        // Skip common URL prefixes like /api, /v1, /v2, /v3
        if (std.ascii.eqlIgnoreCase(s, "api") or
            std.ascii.eqlIgnoreCase(s, "v1") or
            std.ascii.eqlIgnoreCase(s, "v2") or
            std.ascii.eqlIgnoreCase(s, "v3"))
        {
            continue;
        }
        const len = @min(s.len, buf.len);
        @memcpy(buf[0..len], s[0..len]);
        buf[0] = std.ascii.toUpper(buf[0]);
        return buf[0..len];
    }
    return "Default";
}

/// Generates a human-readable summary for an operation (e.g. `List Products`, `Get Products By Id`).
pub fn generateSummary(buf: *[128]u8, method: std.http.Method, path: []const u8, tag: []const u8) []const u8 {
    const has_param = std.mem.indexOf(u8, path, ":") != null;

    return switch (method) {
        .GET => if (has_param)
            std.fmt.bufPrint(buf, "Get {s} By Id", .{tag}) catch "Get Resource"
        else
            std.fmt.bufPrint(buf, "List {s}", .{tag}) catch "List Resources",
        .POST => std.fmt.bufPrint(buf, "Create {s}", .{tag}) catch "Create Resource",
        .PUT => std.fmt.bufPrint(buf, "Update {s}", .{tag}) catch "Update Resource",
        .PATCH => std.fmt.bufPrint(buf, "Partially Update {s}", .{tag}) catch "Update Resource",
        .DELETE => std.fmt.bufPrint(buf, "Delete {s}", .{tag}) catch "Delete Resource",
        else => std.fmt.bufPrint(buf, "{s} {s}", .{ @tagName(method), tag }) catch "Endpoint",
    };
}

/// Generates a unique operation ID string (e.g. `get_products_by_id`).
pub fn generateOperationId(buf: *[128]u8, method: std.http.Method, path: []const u8) []const u8 {
    var out_len: usize = 0;
    const m_name = @tagName(method);
    for (m_name) |c| {
        if (out_len < buf.len) {
            buf[out_len] = std.ascii.toLower(c);
            out_len += 1;
        }
    }
    for (path) |c| {
        if (out_len >= buf.len) break;
        if (c == '/' or c == '-' or c == '.' or c == ':') {
            buf[out_len] = '_';
            out_len += 1;
        } else if (std.ascii.isAlphanumeric(c)) {
            buf[out_len] = std.ascii.toLower(c);
            out_len += 1;
        }
    }
    return buf[0..out_len];
}

/// Generates a clean, valid OpenAPI 3.0.0 JSON schema string containing routes and schemas only.
/// Normalizes paths and deduplicates identical methods on the same route.
/// Caller owns the returned JSON string slice.
pub fn generateJson(self: *const Self, allocator: std.mem.Allocator, routes: []const Route) ![]u8 {
    var json_out: std.ArrayList(u8) = .empty;
    errdefer json_out.deinit(allocator);

    // Collect unique domain tags for schema generation
    var unique_tags = std.StringHashMap(void).init(allocator);
    defer {
        var it = unique_tags.keyIterator();
        while (it.next()) |k| {
            allocator.free(k.*);
        }
        unique_tags.deinit();
    }

    for (routes) |r| {
        var tag_buf: [64]u8 = undefined;
        const raw_tag = extractTag(&tag_buf, r.path);
        if (!unique_tags.contains(raw_tag)) {
            const owned = try allocator.dupe(u8, raw_tag);
            try unique_tags.put(owned, {});
        }
    }

    // Top-level info and paths
    try json_out.appendSlice(allocator, "{\"openapi\":\"3.0.0\",\"info\":{\"title\":\"");
    try json_out.appendSlice(allocator, self.title);
    try json_out.appendSlice(allocator, "\",\"version\":\"");
    try json_out.appendSlice(allocator, self.version);
    try json_out.appendSlice(allocator, "\",\"description\":\"");
    try json_out.appendSlice(allocator, self.description);
    try json_out.appendSlice(allocator, "\"},\"paths\":{");

    // Group routes by normalized OpenAPI path with method deduplication
    var path_map = std.StringHashMap(std.ArrayList(Route)).init(allocator);
    defer {
        var it = path_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        path_map.deinit();
    }

    for (routes) |r| {
        const oas_path = try toOpenApiPath(allocator, r.path);
        if (path_map.getPtr(oas_path)) |list| {
            allocator.free(oas_path);
            // Deduplicate: avoid duplicate method on the same normalized path
            var duplicate = false;
            for (list.items) |existing| {
                if (existing.method == r.method) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) {
                try list.append(allocator, r);
            }
        } else {
            var list: std.ArrayList(Route) = .empty;
            try list.append(allocator, r);
            try path_map.put(oas_path, list);
        }
    }

    var path_iter = path_map.iterator();
    var first_path = true;
    while (path_iter.next()) |entry| {
        if (!first_path) {
            try json_out.append(allocator, ',');
        }
        first_path = false;

        const path_str = entry.key_ptr.*;
        try json_out.append(allocator, '"');
        try json_out.appendSlice(allocator, path_str);
        try json_out.appendSlice(allocator, "\":{");

        var first_method = true;
        for (entry.value_ptr.items) |r| {
            if (!first_method) {
                try json_out.append(allocator, ',');
            }
            first_method = false;

            const method_str = switch (r.method) {
                .GET => "get",
                .POST => "post",
                .PUT => "put",
                .DELETE => "delete",
                .PATCH => "patch",
                .HEAD => "head",
                .OPTIONS => "options",
                else => "get",
            };

            var tag_buf: [64]u8 = undefined;
            const tag = extractTag(&tag_buf, r.path);

            var summary_buf: [128]u8 = undefined;
            const summary = generateSummary(&summary_buf, r.method, r.path, tag);

            var op_buf: [128]u8 = undefined;
            const op_id = generateOperationId(&op_buf, r.method, r.path);

            // Operation header: tags, summary, operationId
            try json_out.append(allocator, '"');
            try json_out.appendSlice(allocator, method_str);
            try json_out.appendSlice(allocator, "\":{\"tags\":[\"");
            try json_out.appendSlice(allocator, tag);
            try json_out.appendSlice(allocator, "\"],\"summary\":\"");
            try json_out.appendSlice(allocator, summary);
            try json_out.appendSlice(allocator, "\",\"operationId\":\"");
            try json_out.appendSlice(allocator, op_id);
            try json_out.append(allocator, '"');

            // Path parameters (only if path includes :param)
            var param_count: usize = 0;
            var param_iter = std.mem.splitScalar(u8, r.path, '/');
            while (param_iter.next()) |seg| {
                if (seg.len > 0 and seg[0] == ':') {
                    param_count += 1;
                }
            }

            if (param_count > 0) {
                try json_out.appendSlice(allocator, ",\"parameters\":[");
                var p_idx: usize = 0;
                var p_iter = std.mem.splitScalar(u8, r.path, '/');
                while (p_iter.next()) |seg| {
                    if (seg.len > 0 and seg[0] == ':') {
                        if (p_idx > 0) try json_out.append(allocator, ',');
                        p_idx += 1;
                        const p_name = seg[1..];
                        const is_num = std.mem.endsWith(u8, p_name, "id") or std.mem.endsWith(u8, p_name, "Id");
                        const schema_type = if (is_num) "{\"type\":\"integer\"}" else "{\"type\":\"string\"}";
                        try json_out.appendSlice(allocator, "{\"name\":\"");
                        try json_out.appendSlice(allocator, p_name);
                        try json_out.appendSlice(allocator, "\",\"in\":\"path\",\"required\":true,\"schema\":");
                        try json_out.appendSlice(allocator, schema_type);
                        try json_out.append(allocator, '}');
                    }
                }
                try json_out.append(allocator, ']');
            }

            // Request body for POST, PUT, PATCH with schema ref
            if (r.method == .POST or r.method == .PUT or r.method == .PATCH) {
                try json_out.appendSlice(allocator, ",\"requestBody\":{\"required\":true,\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/");
                try json_out.appendSlice(allocator, tag);
                try json_out.appendSlice(allocator, "\"}}}}");
            }

            // Responses: 200/201, 400, 404 with schema ref
            try json_out.appendSlice(allocator, ",\"responses\":{\"");
            try json_out.appendSlice(allocator, if (r.method == .POST) "201" else "200");
            try json_out.appendSlice(allocator, "\":{\"description\":\"Successful Response\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/");
            try json_out.appendSlice(allocator, tag);
            try json_out.appendSlice(allocator, "\"}}}},\"400\":{\"description\":\"Bad Request\"},\"404\":{\"description\":\"Not Found\"}}");

            try json_out.append(allocator, '}'); // close method
        }

        try json_out.append(allocator, '}'); // close path
    }

    // Components & Schemas: Clean, simple schemas for each resource
    try json_out.appendSlice(allocator, "},\"components\":{\"schemas\":{");

    var first_schema = true;
    var schema_it = unique_tags.keyIterator();
    while (schema_it.next()) |k| {
        const tag = k.*;
        if (!first_schema) try json_out.append(allocator, ',');
        first_schema = false;

        try json_out.append(allocator, '"');
        try json_out.appendSlice(allocator, tag);
        try json_out.appendSlice(allocator, "\":{\"title\":\"");
        try json_out.appendSlice(allocator, tag);
        try json_out.appendSlice(allocator, "\",\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"},\"name\":{\"type\":\"string\"}}}");
    }

    try json_out.appendSlice(allocator, "}}}");
    return json_out.toOwnedSlice(allocator);
}

/// Serves the clean, standard interactive Swagger UI HTML page at `/docs`.
pub fn serveDocsHtml(res: *Response, openapi_json_url: []const u8) !void {
    const allocator = if (res.request) |r| r.allocator else std.heap.page_allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="utf-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\  <title>Zest API - Swagger UI</title>
        \\  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
        \\  <style>
        \\    body { margin: 0; padding: 0; background: #fafafa; font-family: sans-serif; }
        \\    .topbar { display: none !important; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div id="swagger-ui"></div>
        \\  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>
        \\  <script>
        \\    window.onload = () => {
        \\      window.ui = SwaggerUIBundle({
        \\        url: '
    );
    try out.appendSlice(allocator, openapi_json_url);
    try out.appendSlice(allocator,
        \\',
        \\        dom_id: '#swagger-ui',
        \\        deepLinking: true,
        \\        presets: [
        \\          SwaggerUIBundle.presets.apis,
        \\          SwaggerUIBundle.SwaggerUIStandalonePreset
        \\        ],
        \\        layout: "BaseLayout"
        \\      });
        \\    };
        \\  </script>
        \\</body>
        \\</html>
    );

    try res.html(out.items);
}
