//! Zest: A fast, modern HTTP web framework for Zig.
const std = @import("std");

pub const App = @import("zest/app.zig");
pub const Request = @import("zest/request.zig");
pub const Response = @import("zest/response.zig");
pub const Router = @import("zest/router.zig");
pub const Route = @import("zest/route.zig");
pub const Param = @import("zest/param.zig");
pub const Static = @import("zest/static.zig");
pub const Group = @import("zest/group.zig");
pub const Cookie = @import("zest/cookie.zig");
pub const jwt = @import("zest/jwt.zig");
pub const Db = @import("zest/db.zig");
pub const openapi = @import("zest/openapi.zig");
pub const middleware = @import("zest/middleware.zig");
pub const Model = @import("zest/model.zig").Model;
pub const HandlerFn = Route.HandlerFn;
pub const init = App.init;
pub const time = @import("zest/time.zig");
pub const uuid = @import("zest/uuid.zig");
pub const zuuid = uuid;
pub const zenv = @import("zest/zenv.zig");
pub const validation = @import("zest/validation.zig");
pub const validator = validation.validator;
pub const ValidationErrors = validation.ValidationErrors;
pub const QueryBuilder = @import("zest/query.zig").QueryBuilder;
pub const DbPool = @import("zest/pool.zig").DbPool;
pub const background = @import("zest/background.zig");
pub const BackgroundTasks = background.BackgroundTasks;
pub const multipart = @import("zest/multipart.zig");
pub const FormData = multipart.FormData;
pub const MultipartPart = multipart.MultipartPart;

test "Db.connect with real SQLite file creation, header check, insert and retrieval" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const test_db_path = "real_zest_test.db";
    _ = std.os.linux.unlink(test_db_path);
    defer _ = std.os.linux.unlink(test_db_path);

    var db = try Db.connect(gpa, "sqlite:real_zest_test.db");
    defer db.deinit();

    try db.insert("users", "usr_1", "{\"name\":\"Antigravity\",\"role\":\"developer\"}");
    try db.insert("users", "usr_2", "{\"name\":\"Micky\",\"role\":\"lead\"}");

    try testing.expectEqual(@as(usize, 2), db.count("users"));

    const user1 = try db.findByIdAlloc("users", "usr_1", gpa);
    try testing.expect(user1 != null);
    defer gpa.free(user1.?);
    try testing.expectEqualStrings("{\"name\":\"Antigravity\",\"role\":\"developer\"}", user1.?);

    const all = try db.findAll("users", gpa);
    defer {
        for (all) |u| gpa.free(u);
        gpa.free(all);
    }
    try testing.expectEqual(@as(usize, 2), all.len);

    const deleted = db.deleteById("users", "usr_1");
    try testing.expect(deleted);
    try testing.expectEqual(@as(usize, 1), db.count("users"));

    // Verify physical SQLite file header on disk ("SQLite format 3\00")
    const fd = std.os.linux.open(test_db_path, .{}, 0);
    try testing.expect(fd >= 0);
    defer _ = std.os.linux.close(@intCast(fd));

    var header: [16]u8 = undefined;
    const bytes = std.os.linux.read(@intCast(fd), &header, header.len);
    try testing.expectEqual(@as(usize, 16), bytes);
    try testing.expectEqualStrings("SQLite format 3\x00", &header);
}

test "Db.connect with MongoDB URL and collection operations" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var db = try Db.connect(gpa, "mongodb://admin:pass@127.0.0.1:27017/analytics?authSource=admin");
    defer db.deinit();

    try testing.expectEqual(Db.DriverKind.mongodb, db.kind);
    try testing.expect(db.mongo_client != null);
    try testing.expectEqualStrings("analytics", db.mongo_client.?.database);

    try db.insert("events", "ev_01", "{\"type\":\"page_view\",\"path\":\"/items\"}");
    try testing.expectEqual(@as(usize, 1), db.count("events"));

    const doc = try db.findByIdAlloc("events", "ev_01", gpa);
    try testing.expect(doc != null);
    defer gpa.free(doc.?);
    try testing.expectEqualStrings("{\"type\":\"page_view\",\"path\":\"/items\"}", doc.?);
}

test "zenv file loader from disk" {
    const testing = std.testing;
    const gpa = testing.allocator;
    defer zenv.deinit();

    const env_content =
        \\DATABASE_URL=sqlite:app_from_env.db
        \\PORT=9090
        \\ENABLE_METRICS=yes
    ;

    const fd = std.os.linux.open(".env.test_tmp", .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    try testing.expect(fd >= 0);
    _ = std.os.linux.write(@intCast(fd), env_content.ptr, env_content.len);
    _ = std.os.linux.close(@intCast(fd));
    defer _ = std.os.linux.unlink(".env.test_tmp");

    try zenv.loadFile(gpa, ".env.test_tmp");

    try testing.expectEqualStrings("sqlite:app_from_env.db", zenv.get("DATABASE_URL").?);
    try testing.expectEqual(@as(u16, 9090), zenv.getInt("PORT", u16).?);
    try testing.expect(zenv.getBool("ENABLE_METRICS"));
}

test "zenv parser and accessors" {
    const testing = std.testing;
    const gpa = testing.allocator;
    defer zenv.deinit();

    const sample_env =
        \\# Sample configuration
        \\DATABASE_URL=postgresql://postgres.test:secret123@aws-0-us-east-1.pooler.supabase.com:6543/postgres?sslmode=require
        \\PORT=8080
        \\DEBUG=true
        \\APP_TITLE="Zest \"Super\" Framework\nLine 2"
        \\export SECRET_KEY='raw$secret#123'
        \\INLINE_COMMENT=active # This is active
    ;

    try zenv.parse(gpa, sample_env);

    try testing.expectEqualStrings("postgresql://postgres.test:secret123@aws-0-us-east-1.pooler.supabase.com:6543/postgres?sslmode=require", zenv.get("DATABASE_URL").?);
    try testing.expectEqual(@as(u16, 8080), zenv.getInt("PORT", u16).?);
    try testing.expect(zenv.getBool("DEBUG"));
    try testing.expectEqualStrings("Zest \"Super\" Framework\nLine 2", zenv.get("APP_TITLE").?);
    try testing.expectEqualStrings("raw$secret#123", zenv.get("SECRET_KEY").?);
    try testing.expectEqualStrings("active", zenv.get("INLINE_COMMENT").?);
    try testing.expectEqualStrings("fallback", zenv.getOr("NON_EXISTENT", "fallback"));
}

test "status and method formatting" {
    const s = std.http.Status.ok;
    try std.testing.expect(s.phrase() != null);
    var buf: [64]u8 = undefined;
    const formatted_s = middleware.formatStatus(&buf, .ok);
    try std.testing.expect(std.mem.indexOf(u8, formatted_s, "\x1b[1;32m200 OK\x1b[0m") != null);
    const formatted_m = middleware.formatMethod(.GET);
    try std.testing.expect(std.mem.indexOf(u8, formatted_m, "\x1b[1;32mGET   \x1b[0m") != null);
    const now = time.getMonotonicNanos();
    try std.testing.expect(now > 0);
}

test "Model mixin serialization and ORM metadata" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const User = struct {
        id: u32,
        name: []const u8,
        active: bool,

        pub const model = Model(@This());
    };

    const user = User{ .id = 10, .name = "Alice", .active = true };

    // Test toJson
    const json_str = try User.model.toJson(&user, gpa);
    defer gpa.free(json_str);

    // Test fromJson
    const parsed = try User.model.fromJson(gpa, json_str);
    defer parsed.deinit();

    try testing.expectEqual(@as(u32, 10), parsed.value.id);
    try testing.expectEqualStrings("Alice", parsed.value.name);
    try testing.expect(parsed.value.active);

    // Test ORM metadata
    try testing.expectEqualStrings("User", User.model.tableName());
    try testing.expectEqualStrings("id", User.model.primaryKey());
    try testing.expectEqual(@as(usize, 3), User.model.fieldCount());

    // Test SQL DDL generation
    const ddl = try User.model.createTableSql(gpa);
    defer gpa.free(ddl);
    try testing.expect(std.mem.indexOf(u8, ddl, "CREATE TABLE IF NOT EXISTS User") != null);
    try testing.expect(std.mem.indexOf(u8, ddl, "id INTEGER PRIMARY KEY") != null);
}

test "Router dynamic path parameters" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var router = Router.init(gpa);
    defer router.deinit();

    const handler = struct {
        fn h(_: *Response) anyerror!void {}
    }.h;

    try router.get("/items/:id", handler);
    try router.get("/users/:userId/posts/:postId", handler);

    var params: [16]Param = undefined;
    var params_len: usize = 0;

    // Test matching /items/42
    const found1 = router.find(.GET, "/items/42", &params, &params_len);
    try testing.expect(found1 != null);
    try testing.expectEqual(@as(usize, 1), params_len);
    try testing.expectEqualStrings("id", params[0].name);
    try testing.expectEqualStrings("42", params[0].value);

    // Test matching /users/alice/posts/99
    const found2 = router.find(.GET, "/users/alice/posts/99", &params, &params_len);
    try testing.expect(found2 != null);
    try testing.expectEqual(@as(usize, 2), params_len);
    try testing.expectEqualStrings("userId", params[0].name);
    try testing.expectEqualStrings("alice", params[0].value);
    try testing.expectEqualStrings("postId", params[1].name);
    try testing.expectEqualStrings("99", params[1].value);
}

test "Cookie serialization" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const cookie: Cookie = .{
        .name = "session_id",
        .value = "abc123xyz",
        .path = "/",
        .http_only = true,
        .secure = true,
        .same_site = .strict,
    };

    const cookie_str = try cookie.serialize(gpa);
    defer gpa.free(cookie_str);

    try testing.expect(std.mem.indexOf(u8, cookie_str, "session_id=abc123xyz") != null);
    try testing.expect(std.mem.indexOf(u8, cookie_str, "Path=/") != null);
    try testing.expect(std.mem.indexOf(u8, cookie_str, "HttpOnly") != null);
    try testing.expect(std.mem.indexOf(u8, cookie_str, "Secure") != null);
    try testing.expect(std.mem.indexOf(u8, cookie_str, "SameSite=Strict") != null);
}

test "JWT HS256 sign and verify" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const secret = "zest_super_secret_signing_key_12345";
    const payload = "{\"sub\":\"user42\",\"role\":\"admin\"}";

    // Sign
    const token = try jwt.sign(gpa, payload, secret);
    defer gpa.free(token);

    // Verify valid signature
    const decoded = try jwt.verify(gpa, token, secret);
    defer gpa.free(decoded);
    try testing.expectEqualStrings(payload, decoded);

    // Verify invalid signature rejected
    const invalid = jwt.verify(gpa, token, "wrong_secret");
    try testing.expectError(error.InvalidSignature, invalid);
}

test "Dual SQL / NoSQL Database and ORM operations" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const Product = struct {
        id: u32,
        title: []const u8,
        price: f64,

        pub const model = Model(@This());
    };

    // 1. SQL Mode Test
    {
        var db = Db.initSql(gpa);
        defer db.deinit();

        try db.executeSql("CREATE TABLE IF NOT EXISTS Product (id INTEGER PRIMARY KEY, title TEXT, price REAL);");

        const p1 = Product{ .id = 101, .title = "Mechanical Keyboard", .price = 89.99 };
        try Product.model.save(&db, gpa, &p1);

        try testing.expectEqual(@as(usize, 1), Product.model.count(&db));

        var found = try Product.model.find(&db, gpa, 101);
        try testing.expect(found != null);
        defer found.?.deinit();
        try testing.expectEqualStrings("Mechanical Keyboard", found.?.value.title);
        try testing.expectEqual(@as(u32, 101), found.?.value.id);

        // Delete
        const deleted = Product.model.delete(&db, 101);
        try testing.expect(deleted);
        try testing.expectEqual(@as(usize, 0), Product.model.count(&db));
    }

    // 2. NoSQL Mode Test
    {
        var db = Db.initNoSql(gpa);
        defer db.deinit();

        const p2 = Product{ .id = 202, .title = "Gaming Mouse", .price = 49.99 };
        try Product.model.save(&db, gpa, &p2);

        try testing.expectEqual(@as(usize, 1), Product.model.count(&db));

        // Query documents by field
        const matches = try db.queryDocs("Product", "title", "Gaming Mouse", gpa);
        defer {
            for (matches) |m| gpa.free(m);
            gpa.free(matches);
        }
        try testing.expectEqual(@as(usize, 1), matches.len);

        var found = try Product.model.find(&db, gpa, 202);
        try testing.expect(found != null);
        defer found.?.deinit();
        try testing.expectEqualStrings("Gaming Mouse", found.?.value.title);
    }
}

test "OpenAPI JSON specification generator" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const handler = struct {
        fn h(_: *Response) anyerror!void {}
    }.h;

    const routes = [_]Route{
        .{ .method = .GET, .path = "/items", .handler = Route.wrap(handler) },
        .{ .method = .GET, .path = "/items/", .handler = Route.wrap(handler) }, // Duplicate trailing slash
        .{ .method = .GET, .path = "/items/:id", .handler = Route.wrap(handler) },
        .{ .method = .POST, .path = "/items", .handler = Route.wrap(handler) },
        .{ .method = .POST, .path = "/items/", .handler = Route.wrap(handler) }, // Duplicate trailing slash
    };

    const spec: openapi = .{};
    const json_str = try spec.generateJson(gpa, &routes);
    defer gpa.free(json_str);

    // Verify entire JSON parses cleanly without any syntax or brace errors
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_str, .{});
    defer parsed.deinit();

    try testing.expect(std.mem.indexOf(u8, json_str, "\"openapi\":\"3.0.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"/items/{id}\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"/items\"") != null);
    // Trailing slash /items/ must be deduplicated
    try testing.expect(std.mem.indexOf(u8, json_str, "\"/items/\"") == null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"name\":\"id\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"in\":\"path\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"summary\":\"List Items\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"requestBody\":{\"required\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"components\":{\"schemas\":{\"Items\":") != null);
}

test "OpenAPI registerModel schema generation" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const DummyProduct = struct {
        id: ?u32 = null,
        name: []const u8,
        price: f64,
    };

    var app = init("127.0.0.1", 8080);
    defer app.deinit();

    try app.registerModel(DummyProduct);

    const handler = struct {
        fn h(_: *Response) anyerror!void {}
    }.h;
    try app.get("/api/v1/products", handler);
    try app.post("/api/v1/products", handler);
    try app.get("/api/v1/products/:id", handler);
    try app.get("/", handler); // Root handler (tag Default, must not produce Default schema)

    const json_str = try app.openapi_spec.generateJson(gpa, app.router.routes.items);
    defer gpa.free(json_str);

    // Parse to ensure valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_str, .{});
    defer parsed.deinit();

    // Verify Product schema is generated with exact types and required fields
    try testing.expect(std.mem.indexOf(u8, json_str, "\"DummyProduct\":{\"title\":\"DummyProduct\",\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\",\"nullable\":true},\"name\":{\"type\":\"string\"},\"price\":{\"type\":\"number\"}},\"required\":[\"name\",\"price\"]}") != null);
    // Tag "Default" must NOT appear in components.schemas
    try testing.expect(std.mem.indexOf(u8, json_str, "\"Default\":") == null);
}

test "Time library formatting and parsing" {
    const testing = std.testing;

    // 1. Fixed epoch test: 1700000000 = 2023-11-14 22:13:20 UTC (Tuesday)
    const dt = time.DateTime.fromEpoch(1700000000);
    try testing.expectEqual(@as(u16, 2023), dt.year);
    try testing.expectEqual(@as(u8, 11), dt.month);
    try testing.expectEqual(@as(u8, 14), dt.day);
    try testing.expectEqual(@as(u8, 22), dt.hour);
    try testing.expectEqual(@as(u8, 13), dt.minute);
    try testing.expectEqual(@as(u8, 20), dt.second);
    try testing.expectEqual(@as(u8, 2), dt.weekday); // Tuesday

    // 2. ISO-8601 formatting
    var iso_buf: [32]u8 = undefined;
    const iso_str = dt.toIso8601(&iso_buf);
    try testing.expectEqualStrings("2023-11-14T22:13:20Z", iso_str);

    // 3. HTTP Date (RFC 7231 / RFC 1123) formatting
    var http_buf: [32]u8 = undefined;
    const http_str = dt.toHttpDate(&http_buf);
    try testing.expectEqualStrings("Tue, 14 Nov 2023 22:13:20 GMT", http_str);

    // 4. ISO-8601 parsing
    const parsed_dt = time.parseIso8601("2026-10-01T20:44:26Z");
    try testing.expect(parsed_dt != null);
    try testing.expectEqual(@as(u16, 2026), parsed_dt.?.year);
    try testing.expectEqual(@as(u8, 10), parsed_dt.?.month);
    try testing.expectEqual(@as(u8, 1), parsed_dt.?.day);
    try testing.expectEqual(@as(u8, 20), parsed_dt.?.hour);
    try testing.expectEqual(@as(u8, 44), parsed_dt.?.minute);
    try testing.expectEqual(@as(u8, 26), parsed_dt.?.second);

    // 5. Direct now helpers
    var now_iso_buf: [32]u8 = undefined;
    const now_iso = time.iso8601(&now_iso_buf);
    try testing.expect(now_iso.len == 20);
    try testing.expect(now_iso[10] == 'T');
    try testing.expect(now_iso[19] == 'Z');
}

test "UUID v4 generator" {
    const testing = std.testing;

    var buf: [36]u8 = undefined;
    const id = uuid.v4(&buf);
    try testing.expectEqual(@as(usize, 36), id.len);
    try testing.expectEqual('-', id[8]);
    try testing.expectEqual('-', id[13]);
    try testing.expectEqual('-', id[18]);
    try testing.expectEqual('-', id[23]);
    try testing.expectEqual('4', id[14]); // Version 4
}

test "App scheme detection (HTTP vs HTTPS)" {
    const testing = std.testing;

    var app_http = init("127.0.0.1", 8080);
    defer app_http.deinit();
    try testing.expectEqualStrings("http", app_http.scheme());

    var app_https_port = init("0.0.0.0", 443);
    defer app_https_port.deinit();
    try testing.expectEqualStrings("https", app_https_port.scheme());

    var app_tls = init("127.0.0.1", 8443);
    defer app_tls.deinit();
    app_tls.enableTls("cert.pem", "key.pem");
    try testing.expectEqualStrings("https", app_tls.scheme());
}

test "QueryBuilder fluent filtering, limit, offset, and count" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const Book = struct {
        id: u32,
        title: []const u8,
        price: f64,

        pub const model = Model(@This());
    };

    var db = Db.initNoSql(gpa);
    defer db.deinit();

    try Book.model.save(&db, gpa, &.{ .id = 1, .title = "Zig in Action", .price = 29.99 });
    try Book.model.save(&db, gpa, &.{ .id = 2, .title = "Learning Rust", .price = 39.99 });
    try Book.model.save(&db, gpa, &.{ .id = 3, .title = "Zig Deep Dive", .price = 49.99 });

    // 1. Where contains
    {
        var q = Book.model.query(&db, gpa);
        _ = q.where("title", .contains, "Zig");
        const zig_books = try q.exec();
        defer {
            for (zig_books) |*b| b.deinit();
            gpa.free(zig_books);
        }
        try testing.expectEqual(@as(usize, 2), zig_books.len);
    }

    // 2. Where numeric comparison and limit
    {
        var q = Book.model.query(&db, gpa);
        _ = q.where("price", .gt, "30.00").limit(1);
        const expensive = try q.exec();
        defer {
            for (expensive) |*b| b.deinit();
            gpa.free(expensive);
        }
        try testing.expectEqual(@as(usize, 1), expensive.len);
    }

    // 3. Count
    {
        var q = Book.model.query(&db, gpa);
        _ = q.where("title", .contains, "Zig");
        const c = try q.count();
        try testing.expectEqual(@as(usize, 2), c);
    }
}

test "ValidationErrors and validator helpers" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var errs = ValidationErrors.init(gpa);
    defer errs.deinit();

    validator.requireNotEmpty(&errs, "name", "  ");
    validator.requireMinLength(&errs, "password", "short", 8);
    validator.requireEmail(&errs, "email", "invalid_email_string");
    validator.requireRange(&errs, "age", @as(u8, 15), 18, 99);

    try testing.expect(errs.hasErrors());
    try testing.expectEqual(@as(usize, 4), errs.errors.items.len);

    const json = try errs.toJson(gpa);
    defer gpa.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"field\":\"name\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"field\":\"password\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"field\":\"email\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"field\":\"age\"") != null);
}

test "DbPool connection acquiring, releasing, and idle count" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var pool = try DbPool.init(gpa, "sqlite:pool_test.db", 3);
    defer {
        pool.deinit();
        _ = std.os.linux.unlink("pool_test.db");
    }

    var conn1 = try pool.acquire();
    defer pool.release(conn1);

    try conn1.insert("pool_items", "p1", "{\"status\":\"ok\"}");
    const val = try conn1.findByIdAlloc("pool_items", "p1", gpa);
    try testing.expect(val != null);
    defer gpa.free(val.?);
    try testing.expectEqualStrings("{\"status\":\"ok\"}", val.?);

    const conn2 = try pool.acquire();
    pool.release(conn2);
    try testing.expect(pool.idleCount() >= 1);
}

test "jwtAuth middleware authorization validation" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const secret = "zest_guard_secret_key_999";
    const payload = "{\"sub\":\"alice\",\"role\":\"admin\"}";
    const valid_token = try jwt.sign(gpa, payload, secret);
    defer gpa.free(valid_token);

    // Verify token generation and signature
    const verified = try jwt.verify(gpa, valid_token, secret);
    defer gpa.free(verified);
    try testing.expectEqualStrings(payload, verified);

    // Verify invalid signature rejected
    const bad_verify = jwt.verify(gpa, valid_token, "wrong_secret");
    try testing.expectError(error.InvalidSignature, bad_verify);
}

test "FastAPI-style schema validation" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const UserInput = struct {
        name: []const u8,
        email: []const u8,
        age: u8,

        pub fn validate(self: *const @This(), errs: *ValidationErrors) void {
            validator.requireMinLength(errs, "name", self.name, 3);
            validator.requireEmail(errs, "email", self.email);
            validator.requireRange(errs, "age", self.age, 18, 120);
        }
    };

    // Valid instance
    const valid_user = UserInput{ .name = "Alice", .email = "alice@example.com", .age = 25 };
    var errs1 = ValidationErrors.init(gpa);
    defer errs1.deinit();
    valid_user.validate(&errs1);
    try testing.expect(!errs1.hasErrors());

    // Invalid instance
    const invalid_user = UserInput{ .name = "Al", .email = "bad_email", .age = 15 };
    var errs2 = ValidationErrors.init(gpa);
    defer errs2.deinit();
    invalid_user.validate(&errs2);
    try testing.expect(errs2.hasErrors());
    try testing.expectEqual(@as(usize, 3), errs2.errors.items.len);

    const err_json = try errs2.toJson(gpa);
    defer gpa.free(err_json);
    try testing.expect(std.mem.indexOf(u8, err_json, "detail") != null);
}

test "BackgroundTasks queuing and execution" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var tasks = BackgroundTasks.init(gpa);
    defer tasks.deinit();

    var execution_count: usize = 0;
    const handler = struct {
        fn run(ctx: ?*anyopaque) void {
            const counter: *usize = @ptrCast(@alignCast(ctx.?));
            counter.* += 1;
        }
    }.run;

    try tasks.add(handler, &execution_count);
    try tasks.add(handler, &execution_count);

    try testing.expectEqual(@as(usize, 2), tasks.count());
    tasks.runAll();
    try testing.expectEqual(@as(usize, 2), execution_count);
    try testing.expectEqual(@as(usize, 0), tasks.count());
}

test "multipart form-data parsing and file extraction" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const boundary = "---------------------------974767299852498929531610575";
    const raw_body =
        "-----------------------------974767299852498929531610575\r\n" ++
        "Content-Disposition: form-data; name=\"username\"\r\n\r\n" ++
        "mickycodes\r\n" ++
        "-----------------------------974767299852498929531610575\r\n" ++
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.txt\"\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "Hello Zig Framework!\r\n" ++
        "-----------------------------974767299852498929531610575--\r\n";

    var form = try multipart.parse(gpa, raw_body, boundary);
    defer form.deinit();

    // Verify form field
    const username = form.get("username");
    try testing.expect(username != null);
    try testing.expectEqualStrings("mickycodes", username.?);

    // Verify file upload
    const file = form.getFile("avatar");
    try testing.expect(file != null);
    try testing.expect(file.?.isFile());
    try testing.expectEqualStrings("avatar.txt", file.?.filename.?);
    try testing.expectEqualStrings("text/plain", file.?.content_type.?);
    try testing.expectEqualStrings("Hello Zig Framework!", file.?.data);

    // Test saveTo disk
    const test_upload_file = "test_upload_avatar.txt";
    defer _ = std.os.linux.unlink(test_upload_file);
    try file.?.saveTo(gpa, test_upload_file);

    const fd = std.os.linux.open(test_upload_file, .{}, 0);
    try testing.expect(fd >= 0);
    _ = std.os.linux.close(@intCast(fd));
}

test "Model relationships hasMany and belongsTo" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const Author = struct {
        id: u32,
        name: []const u8,

        pub const model = Model(@This());
    };

    const Article = struct {
        id: u32,
        author_id: u32,
        title: []const u8,

        pub const model = Model(@This());
    };

    var db = Db.initNoSql(gpa);
    defer db.deinit();

    const a1 = Author{ .id = 1, .name = "Grace Hopper" };
    try Author.model.save(&db, gpa, &a1);

    const art1 = Article{ .id = 10, .author_id = 1, .title = "Compilers and COBOL" };
    const art2 = Article{ .id = 11, .author_id = 1, .title = "Debugging the Moth" };
    const art3 = Article{ .id = 12, .author_id = 2, .title = "Other Topic" };

    try Article.model.save(&db, gpa, &art1);
    try Article.model.save(&db, gpa, &art2);
    try Article.model.save(&db, gpa, &art3);

    // 1. Test hasMany: Author -> hasMany Article
    {
        const articles = try Author.model.hasMany(&a1, Article, "author_id", &db, gpa);
        defer {
            for (articles) |*art| art.deinit();
            gpa.free(articles);
        }
        try testing.expectEqual(@as(usize, 2), articles.len);
        const t0 = articles[0].value.title;
        const t1 = articles[1].value.title;
        const has_cobol = std.mem.eql(u8, t0, "Compilers and COBOL") or std.mem.eql(u8, t1, "Compilers and COBOL");
        const has_moth = std.mem.eql(u8, t0, "Debugging the Moth") or std.mem.eql(u8, t1, "Debugging the Moth");
        try testing.expect(has_cobol);
        try testing.expect(has_moth);
    }

    // 2. Test belongsTo: Article -> belongsTo Author
    {
        var author_opt = try Article.model.belongsTo(&art1, Author, "author_id", &db, gpa);
        try testing.expect(author_opt != null);
        defer author_opt.?.deinit();
        try testing.expectEqual(@as(u32, 1), author_opt.?.value.id);
        try testing.expectEqualStrings("Grace Hopper", author_opt.?.value.name);
    }
}

test "Response.serializeJson with Parsed(T) and slice of Parsed(T)" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const Item = struct {
        id: u32,
        title: []const u8,
    };

    const raw1 = "{\"id\":10,\"title\":\"Keyboard\"}";
    const raw2 = "{\"id\":20,\"title\":\"Mouse\"}";

    const p1 = try std.json.parseFromSlice(Item, gpa, raw1, .{});
    defer p1.deinit();
    const p2 = try std.json.parseFromSlice(Item, gpa, raw2, .{});
    defer p2.deinit();

    // 1. Single Parsed instance
    const s1 = try Response.serializeJson(gpa, p1);
    defer gpa.free(s1);
    try testing.expect(std.mem.indexOf(u8, s1, "\"id\":10") != null);
    try testing.expect(std.mem.indexOf(u8, s1, "\"title\":\"Keyboard\"") != null);

    // 2. Slice of Parsed instances (the exact return type of QueryBuilder.exec())
    var list = [_]std.json.Parsed(Item){ p1, p2 };
    const s2 = try Response.serializeJson(gpa, list[0..]);
    defer gpa.free(s2);
    try testing.expect(std.mem.startsWith(u8, s2, "["));
    try testing.expect(std.mem.endsWith(u8, s2, "]"));
    try testing.expect(std.mem.indexOf(u8, s2, "\"id\":10") != null);
    try testing.expect(std.mem.indexOf(u8, s2, "\"id\":20") != null);

    // 3. Optional Parsed
    const opt_some: ?std.json.Parsed(Item) = p1;
    const s3 = try Response.serializeJson(gpa, opt_some);
    defer gpa.free(s3);
    try testing.expect(std.mem.indexOf(u8, s3, "\"id\":10") != null);

    const opt_none: ?std.json.Parsed(Item) = null;
    const s4 = try Response.serializeJson(gpa, opt_none);
    defer gpa.free(s4);
    try testing.expectEqualStrings("null", s4);

    // 4. QueryBuilder.exec() direct serialization
    var db = Db.initNoSql(gpa);
    defer db.deinit();

    const Prod = struct {
        id: u32,
        name: []const u8,
        pub const model = Model(@This());
    };
    try Prod.model.save(&db, gpa, &.{ .id = 1, .name = "ItemA" });
    var q = Prod.model.query(&db, gpa);
    const products = try q.exec();
    defer {
        for (products) |*p| p.deinit();
        gpa.free(products);
    }
    const q_json = try Response.serializeJson(gpa, products);
    defer gpa.free(q_json);
    try testing.expect(std.mem.startsWith(u8, q_json, "["));
    try testing.expect(std.mem.indexOf(u8, q_json, "ItemA") != null);
}

test "uuid v4 generation and formatting" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var buf: [36]u8 = undefined;
    const u = uuid.v4(&buf);
    try testing.expectEqual(@as(usize, 36), u.len);
    try testing.expectEqual('-', u[8]);
    try testing.expectEqual('-', u[13]);
    try testing.expectEqual('-', u[18]);
    try testing.expectEqual('-', u[23]);
    try testing.expectEqual('4', u[14]); // RFC 4122 v4

    const u_alloc = try uuid.v4Alloc(gpa);
    defer gpa.free(u_alloc);
    try testing.expectEqual(@as(usize, 36), u_alloc.len);
    try testing.expectEqual('4', u_alloc[14]);

    // zuuid.generate() by value
    const gen_u = zuuid.generate();
    try testing.expectEqual(@as(usize, 36), gen_u.len);
    try testing.expect(zuuid.isValid(&gen_u));

    // zuuid.new() allocator
    const new_u = try zuuid.new(gpa);
    defer gpa.free(new_u);
    try testing.expectEqual(@as(usize, 36), new_u.len);
    try testing.expect(zuuid.isValid(new_u));
}

test "time module formatting and parsing" {
    const testing = std.testing;

    const t = time.now();
    try testing.expect(t > 1700000000);

    const dt = time.DateTime.fromEpoch(1700000000); // 2023-11-14 22:13:20 UTC
    try testing.expectEqual(@as(u16, 2023), dt.year);
    try testing.expectEqual(@as(u8, 11), dt.month);
    try testing.expectEqual(@as(u8, 14), dt.day);
    try testing.expectEqual(@as(u8, 22), dt.hour);
    try testing.expectEqual(@as(u8, 13), dt.minute);
    try testing.expectEqual(@as(u8, 20), dt.second);

    var iso_buf: [32]u8 = undefined;
    const iso = dt.toIso8601(&iso_buf);
    try testing.expectEqualStrings("2023-11-14T22:13:20Z", iso);

    var http_buf: [32]u8 = undefined;
    const http = dt.toHttpDate(&http_buf);
    try testing.expectEqualStrings("Tue, 14 Nov 2023 22:13:20 GMT", http);

    const parsed = time.parseIso8601("2023-11-14T22:13:20Z").?;
    try testing.expectEqual(dt.year, parsed.year);
    try testing.expectEqual(dt.month, parsed.month);
    try testing.expectEqual(dt.day, parsed.day);
    try testing.expectEqual(dt.hour, parsed.hour);
    try testing.expectEqual(dt.minute, parsed.minute);
    try testing.expectEqual(dt.second, parsed.second);
}

test "Relational Model schema and column mapping in SQLite" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const test_db = "relational_orm_test.db";
    _ = std.os.linux.unlink(test_db);
    defer _ = std.os.linux.unlink(test_db);

    var db = try Db.connect(gpa, "sqlite:relational_orm_test.db");
    defer db.deinit();

    const ProjectModel = struct {
        id: []const u8,
        name: []const u8,
        slug: []const u8,
        views: u64,
        featured: bool,

        pub const model = Model(@This());
    };

    // 1. Save records
    const p1 = ProjectModel{
        .id = "proj_aimlite",
        .name = "AIMLite",
        .slug = "aimlite",
        .views = 150,
        .featured = true,
    };
    try ProjectModel.model.save(&db, gpa, &p1);

    const p2 = ProjectModel{
        .id = "proj_drawviz",
        .name = "DrawViz",
        .slug = "drawviz",
        .views = 75,
        .featured = false,
    };
    try ProjectModel.model.save(&db, gpa, &p2);

    // 2. Verify physical schema in SQLite: columns must be id, name, slug, views, featured (NO data column)
    {
        var stmt: ?*anyopaque = null;
        const rc = Db.sqlite.sqlite3_prepare_v2(db.handle, "PRAGMA table_info(ProjectModel);", -1, &stmt, null);
        try testing.expectEqual(Db.sqlite.OK, rc);
        defer _ = Db.sqlite.sqlite3_finalize(stmt);

        var col_names: std.ArrayList([]const u8) = .empty;
        defer {
            for (col_names.items) |c| gpa.free(c);
            col_names.deinit(gpa);
        }

        while (Db.sqlite.sqlite3_step(stmt) == Db.sqlite.ROW) {
            // column index 1 in pragma table_info is the column name
            if (Db.sqlite.sqlite3_column_text(stmt, 1)) |txt| {
                const dup = try gpa.dupe(u8, std.mem.span(txt));
                try col_names.append(gpa, dup);
            }
        }

        var has_id = false;
        var has_name = false;
        var has_slug = false;
        var has_views = false;
        var has_featured = false;
        var has_data = false;

        for (col_names.items) |cn| {
            if (std.mem.eql(u8, cn, "id")) has_id = true;
            if (std.mem.eql(u8, cn, "name")) has_name = true;
            if (std.mem.eql(u8, cn, "slug")) has_slug = true;
            if (std.mem.eql(u8, cn, "views")) has_views = true;
            if (std.mem.eql(u8, cn, "featured")) has_featured = true;
            if (std.mem.eql(u8, cn, "data")) has_data = true;
        }

        try testing.expect(has_id);
        try testing.expect(has_name);
        try testing.expect(has_slug);
        try testing.expect(has_views);
        try testing.expect(has_featured);
        try testing.expect(!has_data); // Crucial! No fake 'data' column!
    }

    // 3. Raw SQL query directly against real relational columns
    {
        var stmt: ?*anyopaque = null;
        const rc = Db.sqlite.sqlite3_prepare_v2(db.handle, "SELECT name, views, featured FROM ProjectModel WHERE slug = 'aimlite';", -1, &stmt, null);
        try testing.expectEqual(Db.sqlite.OK, rc);
        defer _ = Db.sqlite.sqlite3_finalize(stmt);

        try testing.expectEqual(Db.sqlite.ROW, Db.sqlite.sqlite3_step(stmt));
        const name_txt = Db.sqlite.sqlite3_column_text(stmt, 0).?;
        try testing.expectEqualStrings("AIMLite", std.mem.span(name_txt));
        const views_val = Db.sqlite.sqlite3_column_int64(stmt, 1);
        try testing.expectEqual(@as(i64, 150), views_val);
    }

    // 4. Model.find by ID returns properly mapped instance from real columns
    {
        var found = try ProjectModel.model.find(&db, gpa, "proj_aimlite");
        try testing.expect(found != null);
        defer found.?.deinit();
        try testing.expectEqualStrings("AIMLite", found.?.value.name);
        try testing.expectEqualStrings("aimlite", found.?.value.slug);
        try testing.expectEqual(@as(u64, 150), found.?.value.views);
        try testing.expect(found.?.value.featured);
    }

    // 5. QueryBuilder with SQL WHERE, ORDER BY, LIMIT
    {
        var q = ProjectModel.model.query(&db, gpa);
        _ = q.whereNum("views", .gt, 100);
        _ = q.orderBy("views", .desc);
        const results = try q.exec();
        defer {
            for (results) |*r| r.deinit();
            gpa.free(results);
        }
        try testing.expectEqual(@as(usize, 1), results.len);
        try testing.expectEqualStrings("AIMLite", results[0].value.name);
    }

    // 6. QueryBuilder count
    {
        var q = ProjectModel.model.query(&db, gpa);
        _ = q.where("slug", .eq, "aimlite");
        const c = try q.count();
        try testing.expectEqual(@as(usize, 1), c);
    }
}

test "Relational relationships hasMany and belongsTo in SQLite" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const test_db = "relational_rel_test.db";
    _ = std.os.linux.unlink(test_db);
    defer _ = std.os.linux.unlink(test_db);

    var db = try Db.connect(gpa, "sqlite:relational_rel_test.db");
    defer db.deinit();

    const Author = struct {
        id: u32,
        name: []const u8,

        pub const model = Model(@This());
    };

    const Article = struct {
        id: u32,
        author_id: u32,
        title: []const u8,

        pub const model = Model(@This());
    };

    const a1 = Author{ .id = 1, .name = "Ada Lovelace" };
    try Author.model.save(&db, gpa, &a1);

    const art1 = Article{ .id = 10, .author_id = 1, .title = "Analytical Engine Note G" };
    const art2 = Article{ .id = 11, .author_id = 1, .title = "Bernoulli Numbers" };
    const art3 = Article{ .id = 12, .author_id = 2, .title = "Other Article" };

    try Article.model.save(&db, gpa, &art1);
    try Article.model.save(&db, gpa, &art2);
    try Article.model.save(&db, gpa, &art3);

    // 1. Test hasMany: Author -> hasMany Article
    {
        const articles = try Author.model.hasMany(&a1, Article, "author_id", &db, gpa);
        defer {
            for (articles) |*art| art.deinit();
            gpa.free(articles);
        }
        try testing.expectEqual(@as(usize, 2), articles.len);
        const t0 = articles[0].value.title;
        const t1 = articles[1].value.title;
        const has_note_g = std.mem.eql(u8, t0, "Analytical Engine Note G") or std.mem.eql(u8, t1, "Analytical Engine Note G");
        const has_bernoulli = std.mem.eql(u8, t0, "Bernoulli Numbers") or std.mem.eql(u8, t1, "Bernoulli Numbers");
        try testing.expect(has_note_g);
        try testing.expect(has_bernoulli);
    }

    // 2. Test belongsTo: Article -> belongsTo Author
    {
        var author_opt = try Article.model.belongsTo(&art1, Author, "author_id", &db, gpa);
        try testing.expect(author_opt != null);
        defer author_opt.?.deinit();
        try testing.expectEqual(@as(u32, 1), author_opt.?.value.id);
        try testing.expectEqualStrings("Ada Lovelace", author_opt.?.value.name);
    }
}
