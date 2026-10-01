const std = @import("std");
const Route = @import("route.zig");
const Response = @import("response.zig");

title: []const u8 = "Zest API",
version: []const u8 = "1.0.0",
description: []const u8 = "Fast, modern web API powered by Zest and Zig",

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

/// Generates a valid OpenAPI 3.0.0 JSON schema string from the registered routes.
/// Caller owns the returned JSON string slice.
pub fn generateJson(self: *const Self, allocator: std.mem.Allocator, routes: []const Route) ![]u8 {
    var json_out: std.ArrayList(u8) = .empty;
    errdefer json_out.deinit(allocator);

    const header_str = try std.fmt.allocPrint(allocator, "{{\"openapi\":\"3.0.0\",\"info\":{{\"title\":\"{s}\",\"version\":\"{s}\",\"description\":\"{s}\"}},\"paths\":{{", .{
        self.title,
        self.version,
        self.description,
    });
    defer allocator.free(header_str);
    try json_out.appendSlice(allocator, header_str);

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

            // Extract tag from first path segment
            var tag: []const u8 = "default";
            var seg_iter = std.mem.splitScalar(u8, r.path, '/');
            while (seg_iter.next()) |s| {
                if (s.len > 0 and s[0] != ':') {
                    tag = s;
                    break;
                }
            }

            const method_body = try std.fmt.allocPrint(allocator, "\"{s}\":{{\"summary\":\"{s} {s}\",\"tags\":[\"{s}\"],\"responses\":{{\"200\":{{\"description\":\"Successful Response\"}},\"400\":{{\"description\":\"Bad Request\"}},\"404\":{{\"description\":\"Not Found\"}}}}", .{
                method_str,
                @tagName(r.method),
                r.path,
                tag,
            });
            defer allocator.free(method_body);
            try json_out.appendSlice(allocator, method_body);

            // Detect path parameters
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
                        const param_json = try std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"in\":\"path\",\"required\":true,\"schema\":{{\"type\":\"string\"}}}}", .{seg[1..]});
                        defer allocator.free(param_json);
                        try json_out.appendSlice(allocator, param_json);
                    }
                }
                try json_out.append(allocator, ']');
            }

            try json_out.append(allocator, '}');
        }

        try json_out.append(allocator, '}');
    }

    try json_out.appendSlice(allocator, "}}");
    return json_out.toOwnedSlice(allocator);
}

/// Serves the interactive Swagger UI HTML page at `/docs`.
pub fn serveDocsHtml(res: *Response, openapi_json_url: []const u8) !void {
    const allocator = if (res.request) |r| r.allocator else std.heap.page_allocator;
    const html_content = try std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="utf-8" />
        \\  <meta name="viewport" content="width=device-width, initial-scale=1" />
        \\  <title>Zest API Documentation</title>
        \\  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
        \\  <style>
        \\    body {{ margin: 0; padding: 0; background: #fafafa; font-family: sans-serif; }}
        \\    .topbar {{ display: none !important; }}
        \\  </style>
        \\</head>
        \\<body>
        \\  <div id="swagger-ui"></div>
        \\  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>
        \\  <script>
        \\    window.onload = () => {{
        \\      window.ui = SwaggerUIBundle({{
        \\        url: '{s}',
        \\        dom_id: '#swagger-ui',
        \\        deepLinking: true,
        \\        presets: [
        \\          SwaggerUIBundle.presets.apis,
        \\          SwaggerUIBundle.SwaggerUIStandalonePreset
        \\        ],
        \\        layout: "BaseLayout"
        \\      }});
        \\    }};
        \\  </script>
        \\</body>
        \\</html>
    , .{openapi_json_url});
    defer allocator.free(html_content);

    try res.html(html_content);
}
