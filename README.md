# Zest

A fast, modern, and ergonomic HTTP web framework for Zig.

Zest brings the developer ergonomics and productivity of modern web frameworks (such as FastAPI and Express) into Zig, powered by native non-blocking I/O, compile-time safety, zero-cost abstractions, and thread-safe connection pooling.

---

## Features

- **Express & FastAPI-Inspired Routing**: Dynamic path parameters (`/items/:id`), sub-router route groups (`/api/v1`), and middleware chaining.
- **Universal Database Engine**: First-class support for real SQLite files, PostgreSQL / Supabase (via `libpq`), and MongoDB document collections from a single unified codebase.
- **Fluent ORM & QueryBuilder**: Type-safe querying with filtering (`.where("field", .gte, value)`), sorting, pagination (`.limit()`, `.offset()`), and automated schema synchronization.
- **Model Relationships**: Built-in support for `hasMany` and `belongsTo` associations across both SQL tables and NoSQL collections.
- **FastAPI-Style Validation**: Automatic JSON deserialization, model validation, and structured HTTP 422 Unprocessable Entity error payloads.
- **FastAPI-Style Background Tasks**: Queue tasks (`req.addBackgroundTask`) that execute seamlessly outside the client HTTP response cycle.
- **Multipart Form Data & File Uploads**: Parse `multipart/form-data` streams and save uploaded files directly to disk via `file.saveTo(path)`.
- **Auto-Generated OpenAPI & Swagger UI**: Interactive API documentation automatically served at `/docs` with raw spec at `/openapi.json`.
- **zenv Environment Loader**: Python-like `.env` configuration file loader supporting typed getters (`getInt`, `getBool`, `getOr`), quoted values, and inline comments.
- **Thread-Safe Connection Pooling (`DbPool`)**: Spinlock-protected database connection pool for high-concurrency workloads.
- **Security & Utilities**: HMAC-SHA256 JWT generation and verification, HTTP cookies, and ANSI colored request/response logging.
- **Zero Emojis**: Clean, professional log formatting and terminal output.

---

## Prerequisites

Zest requires **Zig 0.16.0** (or newer) and the standard C runtime libraries for database drivers:

### Ubuntu / Debian
```bash
sudo apt-get install -y libsqlite3-dev libpq-dev
```

### macOS (Homebrew)
```bash
brew install sqlite libpq
```

### Fedora / RHEL / Arch
```bash
# Fedora / RHEL
sudo dnf install -y sqlite-devel libpq-devel

# Arch Linux
sudo pacman -S sqlite postgresql-libs
```

---

## Getting Started

### 1. Add Zest to Your Project

In your Zig project directory, run:

```bash
zig fetch --save git+https://github.com/Alazar42/Zest.git
```

This will automatically add Zest to your `build.zig.zon` dependencies.

### 2. Configure `build.zig`

Update your project's `build.zig` to link the Zest module into your executable:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Fetch Zest package dependency
    const zest_dep = b.dependency("zest", .{
        .target = target,
        .optimize = optimize,
    });

    // 2. Define application executable and import Zest
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zest", .module = zest_dep.module("zest") },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
```

---

## Quickstart Example

Create `src/main.zig`:

```zig
const std = @import("std");
const zest = @import("zest");

// Define a Model with automated validation and ORM mixin
const Item = struct {
    id: u32,
    name: []const u8,
    price: f64,

    pub const model = zest.Model(@This());

    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 2);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};

// Route Handlers
fn getItems(req: *zest.Request, res: *zest.Response) !void {
    // Fluent QueryBuilder
    var q = Item.model.query(&db, req.allocator);
    if (req.queryParam("search")) |s| {
        _ = q.where("name", .contains, s);
    }
    const items = try q.exec();
    defer {
        for (items) |*item| item.deinit();
        req.allocator.free(items);
    }

    try res.jsonValue(items);
}

fn createItem(req: *zest.Request, res: *zest.Response) !void {
    // Validates body with HTTP 422 Unprocessable Entity on failure
    var parsed = (try req.validateJson(Item, res)) orelse return;
    defer parsed.deinit();

    try Item.model.save(&db, req.allocator, &parsed.value);
    try res.status(.created, "{\"status\": \"created\"}");

    // Run asynchronous task after response is sent
    const sendNotification = struct {
        fn run(_: ?*anyopaque) void {
            std.log.info("[Zest] Item created event dispatched in background", .{});
        }
    }.run;
    try req.addBackgroundTask(sendNotification, null);
}

var db: zest.Db = undefined;

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Load .env configuration
    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:app.db");
    const port = zest.zenv.getInt("PORT", u16) orelse 8000;

    // Initialize Database
    db = try zest.Db.connect(gpa, db_url);
    defer db.deinit();

    // Initialize Application
    var app = zest.init("127.0.0.1", port);
    defer app.deinit();

    // Global Middlewares
    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));

    // Interactive Swagger UI at /docs
    app.enableDocs();

    // Routes & Route Groups
    try app.get("/items", getItems);
    try app.post("/items", createItem);

    var api = app.group("/api/v1");
    try api.get("/health", struct {
        fn check(res: *zest.Response) !void {
            try res.json("{\"status\":\"healthy\"}");
        }
    }.check);

    // Start Server
    try app.serve();
}
```

Run the application:
```bash
zig build run
```

---

## Core Capabilities

### 1. Database URL Connection Routing

Connect to any database using standard URL strings:

```zig
// Real SQLite file (auto-creates file and table schemas on disk)
var db = try zest.Db.connect(allocator, "sqlite:data.db");

// PostgreSQL / Supabase
var db = try zest.Db.connect(allocator, "postgresql://user:pass@host:5432/dbname?sslmode=require");

// MongoDB
var db = try zest.Db.connect(allocator, "mongodb://admin:secret@127.0.0.1:27017/dbname");
```

### 2. Model Relationships (`hasMany` and `belongsTo`)

Declare models with relationships:

```zig
const User = struct {
    id: u32,
    username: []const u8,

    pub const model = zest.Model(@This());
};

const Post = struct {
    id: u32,
    user_id: u32,
    title: []const u8,

    pub const model = zest.Model(@This());
};

// Fetch child records: user has many posts
const posts = try User.model.hasMany(&user, Post, "user_id", &db, allocator);
defer {
    for (posts) |*p| p.deinit();
    allocator.free(posts);
}

// Fetch parent record: post belongs to user
var user_opt = try Post.model.belongsTo(&post, User, "user_id", &db, allocator);
if (user_opt) |*u| {
    defer u.deinit();
    std.log.info("Author: {s}", .{u.value.username});
}
```

### 3. Multipart Form Data & File Uploads

```zig
fn handleUpload(req: *zest.Request, res: *zest.Response) !void {
    var form = try req.multipart();
    defer form.deinit();

    // Read form text field
    const title = form.get("title") orelse "Untitled";

    // Read and save file attachment
    if (form.getFile("avatar")) |file| {
        try file.saveTo(req.allocator, "./uploads/avatar.png");
    }

    try res.json("{\"status\":\"uploaded\"}");
}
```

### 4. Background Tasks

Schedule background tasks to execute outside the HTTP request/response cycle:

```zig
fn onUserRegistered(req: *zest.Request, res: *zest.Response) !void {
    // Send immediate HTTP 201 response to client
    try res.status(.created, "{\"message\": \"User registered\"}");

    // Dispatched to background execution after response completes
    const task = struct {
        fn sendWelcomeEmail(ctx: ?*anyopaque) void {
            _ = ctx;
            std.log.info("[Zest] Welcome email sent asynchronously", .{});
        }
    }.sendWelcomeEmail;

    try req.addBackgroundTask(task, null);
}
```

### 5. Environment Variables (`zenv`)

Create a `.env` file in your project root:

```env
PORT=8000
DATABASE_URL=sqlite:production.db
DEBUG=true
API_KEY="secret-token-value"
```

Access variables with type safety:

```zig
try zest.zenv.load(allocator);
defer zest.zenv.deinit();

const port = zest.zenv.getInt("PORT", u16) orelse 8000;
const debug = zest.zenv.getBool("DEBUG");
const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:default.db");
```

---

## Testing

Run the full suite of unit and integration tests:

```bash
zig build test
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
