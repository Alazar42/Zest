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
        .{ .method = .GET, .path = "/items/:id", .handler = Route.wrap(handler) },
        .{ .method = .POST, .path = "/items", .handler = Route.wrap(handler) },
    };

    const spec: openapi = .{};
    const json_str = try spec.generateJson(gpa, &routes);
    defer gpa.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "\"openapi\":\"3.0.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "/items/{id}") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"name\":\"id\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"in\":\"path\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"servers\":[{\"url\":\"/\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"tags\":[{\"name\":\"Items\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"summary\":\"List Items\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"requestBody\":{\"required\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"HTTPValidationError\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"ItemsResponse\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"OAuth2PasswordBearer\"") != null);
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

