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

#### Option A: Starting Fresh with `zig init`
```bash
# 1. Create a new directory and initialize standard Zig layout
mkdir my-zest-api && cd my-zest-api
zig init

# 2. Fetch Zest package into build.zig.zon
zig fetch --save git+https://github.com/Alazar42/Zest.git
```

#### Option B: Adding to an Existing Project
```bash
zig fetch --save git+https://github.com/Alazar42/Zest.git
```

---

### 2. Configure `build.zig`

In your `build.zig` file, you only need to add two lines:

```diff
 pub fn build(b: *std.Build) void {
     const target = b.standardTargetOptions(.{});
     const optimize = b.standardOptimizeOption(.{});
 
+    // 1. Fetch Zest package dependency:
+    const zest_dep = b.dependency("zest", .{
+        .target = target,
+        .optimize = optimize,
+    });
 
     const exe = b.addExecutable(.{
         .name = "my-zest-api",
         .root_module = b.createModule(.{
             .root_source_file = b.path("src/main.zig"),
             .target = target,
             .optimize = optimize,
         }),
     });
+    // 2. Import zest module (automatically links libc, sqlite3, and libpq):
+    exe.root_module.addImport("zest", zest_dep.module("zest"));
 
     b.installArtifact(exe);
 }
```

---

### 3. Updating Zest in an Existing Project

Because Zig uses immutable cryptographic package hashes in `build.zig.zon`, your dependencies will never change unexpectedly. When you want to upgrade or switch versions:

#### Upgrading to the Latest Commit (Recommended)
```bash
zig fetch --save git+https://github.com/Alazar42/Zest.git
```
This updates `.hash` and `.url` in `build.zig.zon` to the latest remote HEAD commit.

#### Pinning a Specific Branch, Tag, or Commit
```bash
# Pin to main branch
zig fetch --save git+https://github.com/Alazar42/Zest.git#main

# Pin to a specific release tag
zig fetch --save git+https://github.com/Alazar42/Zest.git#v0.1.1

# Pin to an exact commit SHA
zig fetch --save git+https://github.com/Alazar42/Zest.git#<commit_sha>
```

#### Local Development Workflow (`.path`)
If you are developing Zest locally alongside your application, switch from `.url` to `.path` in `build.zig.zon`:
```zig
.dependencies = .{
    .zest = .{
        .path = "../Zest", // relative path to local clone
    },
},
```
Local edits to Zest are recompiled immediately on every `zig build run` without git commits!

---

## Architecture & Project Structure

While Zest supports single-file applications for quick scripts, production web services scale best with a clean separation of concerns:

```text
my-zest-api/
├── build.zig
├── build.zig.zon
└── src/
    ├── main.zig              # Entrypoint & server bootstrap
    ├── database.zig          # Shared database connection
    ├── models/
    │   └── product.zig       # Product schema, ORM mixin & validation
    ├── controllers/
    │   └── products.zig      # Request handlers & query logic
    └── routes/
        └── products.zig      # Sub-router route definitions
```

### 1. Model & Validation (`src/models/product.zig`)
```zig
const zest = @import("zest");

pub const Product = struct {
    id: u32,
    name: []const u8,
    price: f64,

    // Universal Comptime ORM Mixin (SQLite, PostgreSQL, MongoDB)
    pub const model = zest.Model(@This());

    // Automated FastAPI-grade Schema Validation
    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 3);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};
```

### 2. Database Lifecycle (`src/database.zig`)
```zig
const std = @import("std");
const zest = @import("zest");

pub var db: zest.Db = undefined;

pub fn init(allocator: std.mem.Allocator, url: []const u8) !void {
    db = try zest.Db.connect(allocator, url);
}

pub fn deinit() void {
    db.deinit();
}
```

### 3. Controller Handlers (`src/controllers/products.zig`)
```zig
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
    // res.jsonValue automatically serializes slices of Parsed models cleanly
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

/// POST /api/v1/products - Creates product with automatic HTTP 422 validation
pub fn create(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    try Product.model.save(&database.db, req.allocator, &parsed.value);
    try res.status(.created, "{\"status\":\"created\"}");
}
```

### 4. Route Registrar (`src/routes/products.zig`)
```zig
const zest = @import("zest");
const products_ctrl = @import("../controllers/products.zig");

pub fn register(g: *zest.Group) !void {
    try g.get("", products_ctrl.getAll);
    try g.get("/", products_ctrl.getAll);
    try g.get("/:id", products_ctrl.getById);
    try g.post("", products_ctrl.create);
    try g.post("/", products_ctrl.create);
}
```

### 5. Application Entrypoint (`src/main.zig`)
```zig
const std = @import("std");
const zest = @import("zest");
const database = @import("database.zig");
const products_routes = @import("routes/products.zig");

fn welcome(res: *zest.Response) !void {
    try res.json("{\"message\": \"Welcome to Zest API! Visit /docs for Swagger UI.\"}");
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // 1. Load .env configuration
    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:products.db");
    const port = zest.zenv.getInt("PORT", u16) orelse 8000;

    // 2. Initialize Database (SQLite, PostgreSQL, or MongoDB)
    try database.init(gpa, db_url);
    defer database.deinit();

    // 3. Initialize Zest Application
    var app = zest.init("127.0.0.1", port);
    defer app.deinit();

    // 4. Middlewares & Swagger UI
    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));
    app.enableDocs(); // Swagger UI at /docs and spec at /openapi.json

    // 5. Mount Routes
    try app.get("/", welcome);

    var api = app.group("/api/v1");
    var products_group = try api.group("/products");
    try products_routes.register(&products_group);

    // 6. Start Server
    std.log.info("Server listening on http://127.0.0.1:{d}", .{port});
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
