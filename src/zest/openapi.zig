const std = @import("std");
const Route = @import("route.zig");
const Response = @import("response.zig");

title: []const u8 = "Zest API",
version: []const u8 = "1.0.0",
description: []const u8 = "High-performance web API powered by Zest and Zig",

const Self = @This();

/// Converts a Zest path with `:param` (e.g. `/items/:id`) into an OpenAPI path template (e.g. `/items/{id}`).
pub fn toOpenApiPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
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

/// Extracts a clean, capitalized domain resource tag from a path (e.g. `/api/v1/items/:id` -> `Items`).
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

/// Generates a FastAPI-grade human-readable summary for an operation (e.g. `List Items`, `Get Items By Id`).
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

/// Generates a detailed FastAPI-grade description explaining the endpoint operation.
pub fn generateDescription(buf: *[256]u8, method: std.http.Method, has_param: bool, tag: []const u8) []const u8 {
    return switch (method) {
        .GET => if (has_param)
            std.fmt.bufPrint(buf, "Retrieve detailed information for a single {s} record by unique ID.", .{tag}) catch "Retrieve resource details"
        else
            std.fmt.bufPrint(buf, "Retrieve a paginated list of {s} records with optional query filtering.", .{tag}) catch "Retrieve resource list",
        .POST => std.fmt.bufPrint(buf, "Create a new {s} record with the provided request body JSON. Returns the created resource.", .{tag}) catch "Create resource",
        .PUT => std.fmt.bufPrint(buf, "Replace and update all attributes of an existing {s} record by unique ID.", .{tag}) catch "Update resource",
        .PATCH => std.fmt.bufPrint(buf, "Partially update specific fields of an existing {s} record by unique ID.", .{tag}) catch "Partially update resource",
        .DELETE => std.fmt.bufPrint(buf, "Permanently delete an existing {s} record from the system by unique ID.", .{tag}) catch "Delete resource",
        else => std.fmt.bufPrint(buf, "Endpoint operation for {s}.", .{tag}) catch "Endpoint operation",
    };
}

/// Generates a unique operation ID string (e.g. `get_items_items_get`).
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

/// Generates a comprehensive FastAPI-grade OpenAPI 3.0.0 JSON schema string from the registered routes.
/// Caller owns the returned JSON string slice.
pub fn generateJson(self: *const Self, allocator: std.mem.Allocator, routes: []const Route) ![]u8 {
    var json_out: std.ArrayList(u8) = .empty;
    errdefer json_out.deinit(allocator);

    // Collect unique domain tags for top-level tags metadata and schema models
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

    // Top-level info, servers, and tags metadata
    const header_str = try std.fmt.allocPrint(allocator, "{{\"openapi\":\"3.0.0\",\"info\":{{\"title\":\"{s}\",\"version\":\"{s}\",\"description\":\"{s}\"}},\"servers\":[{{\"url\":\"/\",\"description\":\"Default Server\"}}],\"tags\":[", .{
        self.title,
        self.version,
        self.description,
    });
    defer allocator.free(header_str);
    try json_out.appendSlice(allocator, header_str);

    var first_tag = true;
    var tag_it = unique_tags.keyIterator();
    while (tag_it.next()) |k| {
        if (!first_tag) try json_out.append(allocator, ',');
        first_tag = false;
        const tag_json = try std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"description\":\"Operations and data models for {s}\"}}", .{ k.*, k.* });
        defer allocator.free(tag_json);
        try json_out.appendSlice(allocator, tag_json);
    }
    try json_out.appendSlice(allocator, "],\"paths\":{");

    // Group routes by OpenAPI path
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
            try list.append(allocator, r);
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
        const path_prefix = try std.fmt.allocPrint(allocator, "\"{s}\":{{", .{path_str});
        defer allocator.free(path_prefix);
        try json_out.appendSlice(allocator, path_prefix);

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

            // Path param detection
            var param_count: usize = 0;
            var param_iter = std.mem.splitScalar(u8, r.path, '/');
            while (param_iter.next()) |seg| {
                if (seg.len > 0 and seg[0] == ':') {
                    param_count += 1;
                }
            }

            var desc_buf: [256]u8 = undefined;
            const desc = generateDescription(&desc_buf, r.method, param_count > 0, tag);

            // Operation header with summary, description, tags, and unique operationId
            const op_header = try std.fmt.allocPrint(allocator, "\"{s}\":{{\"tags\":[\"{s}\"],\"summary\":\"{s}\",\"description\":\"{s}\",\"operationId\":\"{s}\"", .{
                method_str,
                tag,
                summary,
                desc,
                op_id,
            });
            defer allocator.free(op_header);
            try json_out.appendSlice(allocator, op_header);

            // Path & Query Parameters
            const is_get = r.method == .GET;
            const has_query = is_get and param_count == 0;

            if (param_count > 0 or has_query) {
                try json_out.appendSlice(allocator, ",\"parameters\":[");
                var p_idx: usize = 0;

                // Path params
                var p_iter = std.mem.splitScalar(u8, r.path, '/');
                while (p_iter.next()) |seg| {
                    if (seg.len > 0 and seg[0] == ':') {
                        if (p_idx > 0) try json_out.append(allocator, ',');
                        p_idx += 1;
                        const p_name = seg[1..];
                        const is_num = std.mem.endsWith(u8, p_name, "id") or std.mem.endsWith(u8, p_name, "Id");
                        const schema_type = if (is_num) "{\"type\":\"integer\",\"format\":\"int64\",\"example\":1}" else "{\"type\":\"string\",\"example\":\"sample-id\"}";
                        const param_json = try std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"in\":\"path\",\"required\":true,\"description\":\"The unique {s} identifier\",\"schema\":{s}}}", .{
                            p_name,
                            p_name,
                            schema_type,
                        });
                        defer allocator.free(param_json);
                        try json_out.appendSlice(allocator, param_json);
                    }
                }

                // Default search & pagination query parameters for list endpoints
                if (has_query) {
                    if (p_idx > 0) try json_out.append(allocator, ',');
                    try json_out.appendSlice(allocator, "{\"name\":\"search\",\"in\":\"query\",\"required\":false,\"description\":\"Filter records containing substring\",\"schema\":{\"type\":\"string\",\"example\":\"sample\"}},{\"name\":\"limit\",\"in\":\"query\",\"required\":false,\"description\":\"Maximum number of records to return (1-100)\",\"schema\":{\"type\":\"integer\",\"default\":20,\"example\":20}},{\"name\":\"offset\",\"in\":\"query\",\"required\":false,\"description\":\"Number of records to skip for pagination\",\"schema\":{\"type\":\"integer\",\"default\":0,\"example\":0}},{\"name\":\"sort_by\",\"in\":\"query\",\"required\":false,\"description\":\"Field name to sort results by\",\"schema\":{\"type\":\"string\",\"default\":\"id\",\"example\":\"id\"}},{\"name\":\"order\",\"in\":\"query\",\"required\":false,\"description\":\"Sorting direction (asc or desc)\",\"schema\":{\"type\":\"string\",\"enum\":[\"asc\",\"desc\"],\"default\":\"desc\",\"example\":\"desc\"}}");
                }

                try json_out.append(allocator, ']');
            }

            // Interactive requestBody for POST, PUT, PATCH
            if (r.method == .POST or r.method == .PUT or r.method == .PATCH) {
                const body_json = try std.fmt.allocPrint(allocator,
                    \\,"requestBody":{{"required":true,"description":"JSON payload to create or update {s}","content":{{"application/json":{{"schema":{{"$ref":"#/components/schemas/{s}Create"}},"example":{{"name":"Sample {s}","description":"Detailed description for {s}","price":29.99,"is_active":true}}}}}}}}
                , .{ tag, tag, tag, tag });
                defer allocator.free(body_json);
                try json_out.appendSlice(allocator, body_json);
            }

            // Standard Responses (FastAPI-compatible: 200/201, 400, 401, 404, 422)
            if (r.method == .POST) {
                const resp_json = try std.fmt.allocPrint(allocator,
                    \\,"responses":{{"201":{{"description":"Created Successfully - Returns the new {s} record","content":{{"application/json":{{"schema":{{"$ref":"#/components/schemas/{s}Response"}},"example":{{"id":1,"name":"Sample {s}","description":"Detailed description for {s}","price":29.99,"is_active":true,"created_at":"2026-10-01T12:00:00Z"}}}}}}}}
                , .{ tag, tag, tag, tag });
                defer allocator.free(resp_json);
                try json_out.appendSlice(allocator, resp_json);
            } else if (r.method == .DELETE) {
                const resp_json = try std.fmt.allocPrint(allocator,
                    \\,"responses":{{"200":{{"description":"Deleted Successfully - {s} record removed","content":{{"application/json":{{"schema":{{"$ref":"#/components/schemas/SuccessMessage"}},"example":{{"success":true,"message":"Record successfully removed"}}}}}}}}
                , .{tag});
                defer allocator.free(resp_json);
                try json_out.appendSlice(allocator, resp_json);
            } else if (r.method == .GET and param_count == 0) {
                const resp_json = try std.fmt.allocPrint(allocator,
                    \\,"responses":{{"200":{{"description":"Successful Response - Array of {s} records","content":{{"application/json":{{"schema":{{"type":"array","items":{{"$ref":"#/components/schemas/{s}Response"}}}},"example":[{{"id":1,"name":"Sample {s} 1","description":"Detailed description","price":29.99,"is_active":true,"created_at":"2026-10-01T12:00:00Z"}},{{"id":2,"name":"Sample {s} 2","description":"Detailed description","price":49.99,"is_active":true,"created_at":"2026-10-01T12:05:00Z"}}]}}}}}}
                , .{ tag, tag, tag, tag });
                defer allocator.free(resp_json);
                try json_out.appendSlice(allocator, resp_json);
            } else {
                const resp_json = try std.fmt.allocPrint(allocator,
                    \\,"responses":{{"200":{{"description":"Successful Response - Detailed {s} record","content":{{"application/json":{{"schema":{{"$ref":"#/components/schemas/{s}Response"}},"example":{{"id":1,"name":"Sample {s}","description":"Detailed description for {s}","price":29.99,"is_active":true,"created_at":"2026-10-01T12:00:00Z"}}}}}}}}
                , .{ tag, tag, tag, tag });
                defer allocator.free(resp_json);
                try json_out.appendSlice(allocator, resp_json);
            }

            // Append standard error responses (400, 401, 404, 422)
            try json_out.appendSlice(allocator,
                \\,"400":{"description":"Bad Request","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorResponse"},"example":{"error":"Invalid syntax or missing parameters","status":400}}}},"401":{"description":"Unauthorized","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorResponse"},"example":{"error":"Unauthorized: Missing or invalid Bearer token","status":401}}}},"404":{"description":"Not Found","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorResponse"},"example":{"error":"Requested resource not found","status":404}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"},"example":{"detail":[{"loc":["body","name"],"msg":"field required and cannot be empty","type":"value_error.missing"}]}}}}}
            );

            try json_out.append(allocator, '}');
        }

        try json_out.append(allocator, '}');
    }

    // Components & Security Schemas (Bearer Auth + FastAPI ValidationError schemas + dynamic resource models)
    try json_out.appendSlice(allocator,
        \\},"components":{"schemas":{"HTTPValidationError":{"title":"HTTPValidationError","type":"object","properties":{"detail":{"title":"Detail","type":"array","items":{"$ref":"#/components/schemas/ValidationError"}}}},"ValidationError":{"title":"ValidationError","type":"object","required":["loc","msg","type"],"properties":{"loc":{"title":"Location","type":"array","items":{"type":"string"},"example":["body","name"]},"msg":{"title":"Message","type":"string","example":"field required and cannot be empty"},"type":{"title":"Error Type","type":"string","example":"value_error.missing"}}},"ErrorResponse":{"title":"ErrorResponse","type":"object","required":["error","status"],"properties":{"error":{"title":"Error","type":"string","example":"Resource not found"},"status":{"title":"Status","type":"integer","example":404}}},"SuccessMessage":{"title":"SuccessMessage","type":"object","required":["success","message"],"properties":{"success":{"title":"Success","type":"boolean","example":true},"message":{"title":"Message","type":"string","example":"Operation executed successfully"}}}
    );

    // Dynamic model schemas for each unique tag
    var schema_it = unique_tags.keyIterator();
    while (schema_it.next()) |k| {
        const tag = k.*;
        const model_json = try std.fmt.allocPrint(allocator,
            \\,"{s}Response":{{"title":"{s}Response","type":"object","required":["id","name"],"properties":{{"id":{{"title":"ID","type":"integer","format":"int64","example":1}},"name":{{"title":"Name","type":"string","example":"Sample {s}"}},"description":{{"title":"Description","type":"string","example":"Detailed description for {s}"}},"price":{{"title":"Price","type":"number","format":"float","example":29.99}},"is_active":{{"title":"Is Active","type":"boolean","example":true}},"created_at":{{"title":"Created At","type":"string","format":"date-time","example":"2026-10-01T12:00:00Z"}}}}}},"{s}Create":{{"title":"{s}Create","type":"object","required":["name"],"properties":{{"name":{{"title":"Name","type":"string","example":"Sample {s}"}},"description":{{"title":"Description","type":"string","example":"Detailed description for {s}"}},"price":{{"title":"Price","type":"number","format":"float","example":29.99}},"is_active":{{"title":"Is Active","type":"boolean","example":true}}}}}}
        , .{ tag, tag, tag, tag, tag, tag, tag, tag });
        defer allocator.free(model_json);
        try json_out.appendSlice(allocator, model_json);
    }

    try json_out.appendSlice(allocator,
        \\},"securitySchemes":{"OAuth2PasswordBearer":{"type":"http","scheme":"bearer","bearerFormat":"JWT","description":"Enter your Bearer JWT token to authenticate requests"}}},"security":[{"OAuth2PasswordBearer":[]}]}
    );

    return json_out.toOwnedSlice(allocator);
}

/// Serves the interactive Swagger UI HTML page at `/docs`.
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
        \\  <title>Zest API Documentation</title>
        \\  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
        \\  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
        \\  <style>
        \\    body { margin: 0; padding: 0; background: #fafafa; font-family: 'Inter', -apple-system, sans-serif; }
        \\    .topbar { display: none !important; }
        \\    .zest-banner {
        \\      background: linear-gradient(135deg, #111827 0%, #1f2937 100%);
        \\      color: white;
        \\      padding: 14px 28px;
        \\      display: flex;
        \\      align-items: center;
        \\      justify-content: space-between;
        \\      border-bottom: 2px solid #10b981;
        \\      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        \\    }
        \\    .zest-brand { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 1.15rem; }
        \\    .zest-pill { background: #10b981; color: #111827; font-size: 0.75rem; padding: 3px 8px; border-radius: 9999px; font-weight: 700; }
        \\    .zest-links { display: flex; gap: 16px; font-size: 0.85rem; }
        \\    .zest-links a { color: #9ca3af; text-decoration: none; font-weight: 500; transition: color 0.15s; }
        \\    .zest-links a:hover { color: #10b981; }
        \\    .swagger-ui .info { margin: 25px 0 15px 0 !important; }
        \\    .swagger-ui .btn.authorize { color: #10b981; border-color: #10b981; }
        \\    .swagger-ui .btn.authorize svg { fill: #10b981; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="zest-banner">
        \\    <div class="zest-brand">
        \\      <span>⚡ Zest API</span>
        \\      <span class="zest-pill">v1.0.0</span>
        \\    </div>
        \\    <div class="zest-links">
        \\      <a href="/redoc">ReDoc Documentation</a>
        \\      <a href="
    );
    try out.appendSlice(allocator, openapi_json_url);
    try out.appendSlice(allocator,
        \\" target="_blank">OpenAPI Spec (JSON)</a>
        \\    </div>
        \\  </div>
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
        \\        persistAuthorization: true,
        \\        displayRequestDuration: true,
        \\        filter: true,
        \\        showExtensions: true,
        \\        showCommonExtensions: true,
        \\        tryItOutEnabled: true,
        \\        docExpansion: "list",
        \\        defaultModelsExpandDepth: 2,
        \\        defaultModelExpandDepth: 2,
        \\        syntaxHighlight: { theme: "monokai" },
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

/// Serves the ReDoc documentation HTML page at `/redoc`.
pub fn serveRedocHtml(res: *Response, openapi_json_url: []const u8) !void {
    const allocator = if (res.request) |r| r.allocator else std.heap.page_allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="utf-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\  <title>Zest API Documentation - ReDoc</title>
        \\  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet" />
        \\  <style>
        \\    body { margin: 0; padding: 0; font-family: 'Inter', sans-serif; }
        \\    .zest-redoc-header {
        \\      background: linear-gradient(135deg, #111827 0%, #1f2937 100%);
        \\      color: white;
        \\      padding: 12px 24px;
        \\      display: flex;
        \\      align-items: center;
        \\      justify-content: space-between;
        \\      border-bottom: 2px solid #10b981;
        \\    }
        \\    .zest-redoc-brand { font-weight: 700; font-size: 1.1rem; display: flex; align-items: center; gap: 8px; }
        \\    .zest-redoc-links a { color: #9ca3af; text-decoration: none; margin-left: 16px; font-size: 0.85rem; font-weight: 500; }
        \\    .zest-redoc-links a:hover { color: #10b981; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="zest-redoc-header">
        \\    <div class="zest-redoc-brand">
        \\      <span>⚡ Zest API</span>
        \\      <span style="background:#10b981;color:#111827;font-size:0.75rem;padding:2px 8px;border-radius:9999px;">ReDoc</span>
        \\    </div>
        \\    <div class="zest-redoc-links">
        \\      <a href="/docs">Swagger UI (/docs)</a>
        \\      <a href="
    );
    try out.appendSlice(allocator, openapi_json_url);
    try out.appendSlice(allocator,
        \\" target="_blank">OpenAPI Spec (JSON)</a>
        \\    </div>
        \\  </div>
        \\  <redoc spec-url="
    );
    try out.appendSlice(allocator, openapi_json_url);
    try out.appendSlice(allocator,
        \\"></redoc>
        \\  <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
        \\</body>
        \\</html>
    );

    try res.html(out.items);
}
