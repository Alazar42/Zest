export const DOCS_SECTIONS = [
  {
    id: 'getting-started',
    title: 'Getting Started',
    items: [
      { id: 'introduction', title: 'Introduction' },
      { id: 'prerequisites', title: 'Prerequisites' },
      { id: 'installation', title: 'Installation & zig init' },
      { id: 'build-zig', title: 'Configuring build.zig' },
      { id: 'updating-zest', title: 'Updating Zest' },
      { id: 'quickstart', title: 'Quickstart & Architecture' }
    ]
  },
  {
    id: 'routing-http',
    title: 'HTTP & Routing Guide',
    items: [
      { id: 'router', title: 'Router & Route Handlers' },
      { id: 'path-params', title: 'Path Parameters' },
      { id: 'query-params', title: 'Query Parameters & Filters' },
      { id: 'sub-routers', title: 'Sub-Router Route Groups' },
      { id: 'request-response', title: 'Request & Response API' },
      { id: 'response-status', title: 'Response Status & Formatting' },
      { id: 'error-handling', title: 'Error Handling & HTTP Exceptions' },
      { id: 'headers-cookies', title: 'Headers & Cookies' },
      { id: 'middleware', title: 'Middlewares & Logging' }
    ]
  },
  {
    id: 'database-engine',
    title: 'Universal Database',
    items: [
      { id: 'db-architecture', title: 'Unified Engine Architecture' },
      { id: 'sqlite-driver', title: 'Real SQLite Persistence' },
      { id: 'postgres-driver', title: 'PostgreSQL & Supabase' },
      { id: 'mongo-driver', title: 'MongoDB Document Engine' },
      { id: 'db-pooling', title: 'Connection Pooling (DbPool)' }
    ]
  },
  {
    id: 'orm-models',
    title: 'Models & ORM',
    items: [
      { id: 'model-mixin', title: 'Model Mixin & DDL Sync' },
      { id: 'query-builder', title: 'Fluent QueryBuilder' },
      { id: 'relationships', title: 'Relationships (hasMany & belongsTo)' }
    ]
  },
  {
    id: 'advanced-features',
    title: 'Advanced Capabilities',
    items: [
      { id: 'validation', title: 'Validation & HTTP 422 Errors' },
      { id: 'background-tasks', title: 'FastAPI Background Tasks' },
      { id: 'multipart-uploads', title: 'Multipart Form Data & Uploads' },
      { id: 'openapi-swagger', title: 'Swagger UI & OpenAPI 3.0' },
      { id: 'uuid-generator', title: 'UUID v4 Engine (zuuid)' },
      { id: 'time-datetime', title: 'Time & DateTime (zest.time)' },
      { id: 'zenv-loader', title: 'Environment Loader (zenv)' },
      { id: 'jwt-security', title: 'JWT Authentication & Cookies' },
      { id: 'auth-middleware', title: 'Route Guards & Role-Based Auth' }
    ]
  },
  {
    id: 'production-deployment',
    title: 'Testing & Production',
    items: [
      { id: 'testing-guide', title: 'Testing Guide & Test Cases' },
      { id: 'deployment-docker', title: 'Production & Docker Guide' }
    ]
  }
];

export const DOCS_CONTENT = {
  'introduction': {
    title: 'Introduction to Zest',
    subtitle: 'A high-performance, modern HTTP web framework designed natively for Zig.',
    content: `
Zest combines the productivity and developer ergonomics of modern web frameworks (such as FastAPI and Express) with the raw execution speed, safety, and zero-overhead memory control of Zig.

### Core Architecture Pillars

1. **Zero-Allocation Hot Paths**: Route matching and URL parsing operate with zero heap allocations on high-throughput requests.
2. **Universal Database Routing**: Seamlessly switch between SQLite on local disk, PostgreSQL / Supabase via \`libpq\`, and MongoDB collections using standard database connection strings without altering business logic or model definitions.
3. **Comptime Reflection**: Zig's compile-time introspection (\`comptime\`) automates JSON serialization, SQL DDL table generation, and relationship mapping with zero runtime reflection overhead.
4. **FastAPI-Grade Ergonomics**: Includes automated request body validation with structured HTTP 422 Unprocessable Entity error payloads, asynchronous background tasks, and interactive Swagger UI documentation out of the box.
    `,
    codeExamples: [
      {
        title: 'Minimal Zest Application (src/main.zig)',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

fn helloHandler(res: *zest.Response) !void {
    try res.json(.{ .message = "Hello, Zest!" });
}

pub fn main() !void {
    var app = zest.init("127.0.0.1", 8000);
    defer app.deinit();

    try app.use(zest.middleware.logger);
    try app.get("/", helloHandler);

    try app.serve();
}`
      }
    ]
  },

  'prerequisites': {
    title: 'Prerequisites & System Libraries',
    subtitle: 'System requirements and driver dependencies.',
    content: `
Zest requires **Zig 0.16.0** or newer. Because Zest provides universal database drivers for real physical SQLite files and PostgreSQL / Supabase, the standard C development headers for \`sqlite3\` and \`libpq\` must be installed on your development host.

### Installing Dependencies by Operating System

#### Ubuntu / Debian / WSL
Run the following command in your terminal:
\`\`\`bash
sudo apt-get update && sudo apt-get install -y libsqlite3-dev libpq-dev
\`\`\`

#### macOS (via Homebrew)
\`\`\`bash
brew install sqlite libpq
\`\`\`

#### Arch Linux
\`\`\`bash
sudo pacman -S sqlite postgresql-libs
\`\`\`

#### Fedora / RHEL
\`\`\`bash
sudo dnf install -y sqlite-devel libpq-devel
\`\`\`
    `,
    codeExamples: []
  },

  'installation': {
    title: 'Package Installation & Setup',
    subtitle: 'Adding Zest to your project using zig init or an existing repository.',
    content: `
Zest integrates directly into Zig's native package manager without external package tools. You can start either from a brand new project initialized with \`zig init\` or add Zest to an existing codebase.

### Option A: Starting a New Project with \`zig init\`

To create a brand new Zig project with Zest:

\`\`\`bash
# 1. Create a new project directory
mkdir my-zest-api && cd my-zest-api

# 2. Initialize a standard Zig executable & library structure
zig init

# 3. Add Zest as a dependency to your build.zig.zon
zig fetch --save git+https://github.com/Alazar42/Zest.git
\`\`\`

The \`zig init\` command generates:
- \`build.zig\`: The build script orchestrating your compilation.
- \`build.zig.zon\`: The Zig Object Notation package manifest.
- \`src/main.zig\`: The executable entrypoint.
- \`src/root.zig\`: The library entrypoint.

### Option B: Adding to an Existing Project

If you already have a Zig project, simply navigate to your project root and fetch Zest:

\`\`\`bash
zig fetch --save git+https://github.com/Alazar42/Zest.git
\`\`\`

This automatically computes the SHA-256 cryptographic hash and registers Zest under \`.dependencies\` in your \`build.zig.zon\`.
    `,
    codeExamples: [
      {
        title: 'Resulting build.zig.zon snippet',
        language: 'zig',
        code: `.{
    .name = .my_zest_api,
    .version = "0.1.0",
    .fingerprint = 0xe5383c71202cbc31,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .zest = .{
            .url = "git+https://github.com/Alazar42/Zest.git",
            .hash = "zest-0.1.0-X3O6mD9_AgAC9_lSdzqqZq06Ugsia7ymDKQgc9vHlYHk",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}`
      }
    ]
  },

  'build-zig': {
    title: 'Configuring build.zig (Line-by-Line)',
    subtitle: 'Integrate Zest into zig init or existing build scripts with only two lines.',
    content: `
Configuring \`build.zig\` requires only two additions: declaring the package dependency and importing the module into your executable.

### 1. For Standard \`zig init\` Projects
When you initialize a project using \`zig init\`, Zig creates an executable \`exe = b.addExecutable(...)\`. You only need to add:

1. **Declare the dependency** (right after target and optimize options):
\`\`\`zig
const zest_dep = b.dependency("zest", .{
    .target = target,
    .optimize = optimize,
});
\`\`\`

2. **Add the import to your executable**:
\`\`\`zig
exe.root_module.addImport("zest", zest_dep.module("zest"));
\`\`\`

> **Automatic Driver Linking**: Zest automatically links \`sqlite3\`, \`libpq\` (PostgreSQL), and \`libc\` into the imported module. You do not need to manually configure \`linkSystemLibrary\` in your own build script unless your project calls C APIs directly.
    `,
    codeExamples: [
      {
        title: 'Complete Diff for an Existing build.zig',
        language: 'diff',
        code: ` pub fn build(b: *std.Build) void {
     const target = b.standardTargetOptions(.{});
     const optimize = b.standardOptimizeOption(.{});
 
+    // 1. Fetch Zest package dependency:
+    const zest_dep = b.dependency("zest", .{
+        .target = target,
+        .optimize = optimize,
+    });
 
     const exe = b.addExecutable(.{
         .name = "my-service",
         .root_module = b.createModule(.{
             .root_source_file = b.path("src/main.zig"),
             .target = target,
             .optimize = optimize,
         }),
     });
 
+    // 2. Add the zest module import:
+    exe.root_module.addImport("zest", zest_dep.module("zest"));
 
     b.installArtifact(exe);
 }`
      }
    ]
  },

  'updating-zest': {
    title: 'Updating Zest in an Existing Project',
    subtitle: 'How to upgrade, pin specific versions, and switch between git and local development.',
    content: `
When you add Zest to your project via \`zig fetch --save\`, Zig locks the exact commit SHA and computed content hash inside your \`build.zig.zon\` manifest.

Because Zig uses immutable package content hashes, running \`zig build\` will **never** automatically pull remote changes unexpectedly. When you want to update Zest to a newer version or bugfix release, use one of the methods below.

---

### Method 1: Upgrading to the Latest Commit (Recommended)

To pull the latest commit from the main repository and update your \`build.zig.zon\` hash:

\`\`\`bash
zig fetch --save git+https://github.com/Alazar42/Zest.git
\`\`\`

Zig will contact GitHub, fetch the newest HEAD commit, compute its new cryptographic fingerprint, and rewrite the \`.hash\` and \`.url\` fields in \`build.zig.zon\` automatically.

---

### Method 2: Pinning a Specific Branch, Tag, or Commit

You can append a fragment identifier (\`#<ref>\`) to the URL to pin an exact git reference:

#### Update to the \`main\` branch explicitly:
\`\`\`bash
zig fetch --save git+https://github.com/Alazar42/Zest.git#main
\`\`\`

#### Pin to a specific release tag:
\`\`\`bash
zig fetch --save git+https://github.com/Alazar42/Zest.git#v0.1.1
\`\`\`

#### Pin to an exact Git commit SHA:
\`\`\`bash
zig fetch --save git+https://github.com/Alazar42/Zest.git#1b4c8e0ce752a7c7bd2beb61a473255cb56faf29
\`\`\`

---

### Method 3: Forcing Cache Invalidation

If your development machine cached an older package version, or you need to ensure all dependencies are clean:

\`\`\`bash
# 1. Force Zig to re-fetch all declared dependencies
zig build --fetch

# 2. Clear local build cache if required
rm -rf .zig-cache
\`\`\`

---

### Method 4: Local Framework Development Workflow (\`.path\`)

If you are developing Zest itself, writing custom extensions, or debugging framework internals alongside your application, you do **not** need to push git commits to test changes.

Simply switch your dependency in \`build.zig.zon\` from a \`.url\` to a relative \`.path\`:

\`\`\`zig
// build.zig.zon
.{
    .name = .my_app,
    .version = "0.1.0",
    .fingerprint = 0xe5383c71202cbc31,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .zest = .{
            // Point directly to your local clone of Zest:
            .path = "../Zest",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
\`\`\`

With \`.path\`, any changes made to the Zest source code are compiled **instantly** on your next \`zig build run\` with zero fetch latency!
    `,
    codeExamples: [
      {
        title: 'Updating Dependencies Command Cheatsheet',
        language: 'bash',
        code: `# Upgrade Zest to latest commit
zig fetch --save git+https://github.com/Alazar42/Zest.git

# Rebuild your application with the new version
zig build run

# Verify compilation and run all tests
zig build test`
      }
    ]
  },

  'quickstart': {
    title: 'Quickstart & Project Architecture',
    subtitle: 'Structuring scalable Zest applications with controllers, models, and routes.',
    content: `
While Zest easily supports single-file applications for quick scripts and microservices, production web applications scale best with a clean separation of concerns:

- **\`src/models/\`**: Domain structs, validation schemas, and ORM table mappings.
- **\`src/database.zig\`**: Centralized database connection lifecycle and pooling.
- **\`src/controllers/\`**: HTTP handlers that process requests, query data, and return responses.
- **\`src/routes/\`**: Endpoint declarations grouped by sub-router or domain resource.
- **\`src/main.zig\`**: Application entrypoint: loads configuration, configures middlewares, mounts routes, and starts the server.

### Recommended Project Layout

\`\`\`text
my-zest-api/
├── build.zig
├── build.zig.zon
└── src/
    ├── main.zig              # Entrypoint & server bootstrap
    ├── database.zig          # Shared database connection
    ├── models/
    │   └── product.zig       # Product schema & validation
    ├── controllers/
    │   └── products.zig      # Request handlers & logic
    └── routes/
        └── products.zig      # Sub-router route definitions
\`\`\`

Review the complete working files below. You can copy this structure directly into your project:
    `,
    codeExamples: [
      {
        title: '1. src/models/product.zig (Model & Validation Schema)',
        language: 'zig',
        code: `const zest = @import("zest");

pub const Product = struct {
    id: ?[]const u8 = null,
    name: []const u8,
    price: f64,

    // Universal Comptime ORM Mixin (SQLite, PostgreSQL, MongoDB)
    pub const model = zest.Model(@This());

    // Automated FastAPI-grade Schema Validation
    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 3);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};`
      },
      {
        title: '2. src/database.zig (Database Lifecycle)',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

pub var db: zest.Db = undefined;

/// Connects to real SQLite, PostgreSQL / Supabase, or MongoDB based on the URL scheme.
pub fn init(allocator: std.mem.Allocator, url: []const u8) !void {
    db = try zest.Db.connect(allocator, url);
}

pub fn deinit() void {
    db.deinit();
}`
      },
      {
        title: '3. src/controllers/products.zig (Controller Handlers)',
        language: 'zig',
        code: `const std = @import("std");
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
    try res.json(products);
}

/// GET /api/v1/products/:id - Fetch single product by UUID
pub fn getById(req: *zest.Request, res: *zest.Response) !void {
    const id = req.param("id") orelse {
        try res.status(.bad_request, .{ .@"error" = "Missing product ID" });
        return;
    };

    var found = try Product.model.find(&database.db, req.allocator, id);
    if (found) |*p| {
        defer p.deinit();
        try res.json(p.value);
    } else {
        try res.status(.not_found, .{ .@"error" = "Product not found" });
    }
}

/// POST /api/v1/products - Creates product with auto-generated UUID v4 if not provided
pub fn create(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    var product = parsed.value;
    if (product.id == null or product.id.?.len == 0) {
        product.id = try zest.zuuid.new(req.allocator);
    }

    try Product.model.save(&database.db, req.allocator, &product);
    try res.status(.created, .{ .status = "created", .id = product.id.? });
}

/// DELETE /api/v1/products/:id - Delete product by UUID
pub fn deleteProduct(req: *zest.Request, res: *zest.Response) !void {
    const id = req.param("id") orelse {
        try res.status(.bad_request, .{ .@"error" = "Missing product ID" });
        return;
    };

    if (Product.model.delete(&database.db, id)) {
        try res.json(.{ .message = "Product deleted successfully" });
    } else {
        try res.status(.not_found, .{ .@"error" = "Product not found" });
    }
}`
      },
      {
        title: '4. src/routes/products.zig (Route Registrar)',
        language: 'zig',
        code: `const zest = @import("zest");
const products_ctrl = @import("../controllers/products.zig");

/// Registers all product endpoints on the provided router or route group.
pub fn register(g: *zest.Group) !void {
    try g.get("", products_ctrl.getAll);
    try g.get("/", products_ctrl.getAll);
    try g.get("/:id", products_ctrl.getById);
    try g.post("", products_ctrl.create);
    try g.post("/", products_ctrl.create);
    try g.delete("/:id", products_ctrl.deleteProduct);
}`
      },
      {
        title: '5. src/main.zig (Application Entrypoint)',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");
const database = @import("database.zig");
const Product = @import("models/product.zig").Product;
const products_routes = @import("routes/products.zig");

fn welcome(res: *zest.Response) !void {
    try res.json(.{ .message = "Welcome to Zest API! Visit /docs for Swagger UI." });
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // 1. Load .env configuration
    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:products.db");
    const port = zest.zenv.getInt("PORT", u16) orelse 8000;

    // 2. Initialize Database and seed sample products
    try database.init(gpa, db_url);
    defer database.deinit();

    try Product.model.save(&database.db, gpa, &.{ .id = &zest.zuuid.generate(), .name = "Apple iPhone", .price = 999.99 });
    try Product.model.save(&database.db, gpa, &.{ .id = &zest.zuuid.generate(), .name = "MacBook Pro", .price = 1999.99 });

    // 3. Initialize Zest Application
    var app = zest.init("127.0.0.1", port);
    defer app.deinit();

    // 4. Middlewares & Swagger UI
    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));
    app.enableDocs(); // Serves Swagger UI at /docs and spec at /openapi.json
    try app.registerModel(Product);

    // 5. Mount Root Route & Sub-Router Group
    try app.get("/", welcome);

    var api = app.group("/api/v1");
    var products_group = try api.group("/products");
    try products_routes.register(&products_group);

    // 6. Start Server
    std.log.info("Server listening on http://127.0.0.1:{d}", .{port});
    try app.serve();
}`
      },
      {
        title: 'Alternative: Single-File Microservice (src/main.zig)',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

// For quick scripts or microservices, all components can live in one file:
const Product = struct {
    id: ?[]const u8 = null,
    name: []const u8,
    price: f64,

    pub const model = zest.Model(@This());

    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 3);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};

var db: zest.Db = undefined;

fn listProducts(req: *zest.Request, res: *zest.Response) !void {
    var q = Product.model.query(&db, req.allocator);
    if (req.queryParam("search")) |s| {
        _ = q.where("name", .contains, s);
    }
    const products = try q.exec();
    defer {
        for (products) |*p| p.deinit();
        req.allocator.free(products);
    }
    try res.json(products);
}

fn createProduct(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    var product = parsed.value;
    if (product.id == null or product.id.?.len == 0) {
        product.id = try zest.zuuid.new(req.allocator);
    }

    try Product.model.save(&db, req.allocator, &product);
    try res.status(.created, .{ .status = "created", .id = product.id.? });
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    db = try zest.Db.connect(gpa, zest.zenv.getOr("DATABASE_URL", "sqlite:products.db"));
    defer db.deinit();

    try Product.model.save(&db, gpa, &.{ .id = &zest.zuuid.generate(), .name = "Apple iPhone", .price = 999.99 });
    try Product.model.save(&db, gpa, &.{ .id = &zest.zuuid.generate(), .name = "MacBook Pro", .price = 1999.99 });

    var app = zest.init("127.0.0.1", zest.zenv.getInt("PORT", u16) orelse 8000);
    defer app.deinit();

    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));
    app.enableDocs();
    try app.registerModel(Product);

    try app.get("/products", listProducts);
    try app.post("/products", createProduct);

    try app.serve();
}`
      }
    ]
  },

  'router': {
    title: 'Router & Route Handlers',
    subtitle: 'High-performance trie-based HTTP method dispatching.',
    content: `
Zest supports all standard HTTP methods: \`get\`, \`post\`, \`put\`, \`delete\`, \`patch\`, and \`options\`. Route handlers can be written in two flexible styles:

1. **Pure Response**: \`fn handler(res: *zest.Response) !void\`
2. **Full Context**: \`fn handler(req: *zest.Request, res: *zest.Response) !void\`
    `,
    codeExamples: [
      {
        title: 'Route Definitions',
        language: 'zig',
        code: `// GET handler
try app.get("/health", struct {
    fn check(res: *zest.Response) !void {
        try res.json(.{ .status = "ok" });
    }
}.check);

// POST handler with request inspection
try app.post("/echo", struct {
    fn echo(req: *zest.Request, res: *zest.Response) !void {
        try res.send(req.body);
    }
}.echo);`
      }
    ]
  },

  'path-params': {
    title: 'Dynamic Path Parameters',
    subtitle: 'Extract typed route variables with zero manual string parsing.',
    content: `
Routes with segments starting with \`:\` define dynamic parameters (e.g. \`/users/:id/orders/:order_id\`).

### Available Extractors
- \`req.param(name)\`: Returns \`?[]const u8\` slice.
- \`req.paramInt(name, Type)\`: Parses directly into integer types (\`u32\`, \`u64\`, \`i32\`).
- \`req.queryParam(name)\`: Extracts query string variables (\`?limit=10\`).
    `,
    codeExamples: [
      {
        title: 'Extracting Path & Query Parameters',
        language: 'zig',
        code: `fn getUser(req: *zest.Request, res: *zest.Response) !void {
    const user_id = req.paramInt("id", u32) orelse {
        try res.status(.bad_request, .{ .@"error" = "Invalid user ID" });
        return;
    };

    const include_history = req.queryParam("history") != null;

    // Fetch user record...
    try res.json(.{ .user_id = user_id });
}`
      }
    ]
  },

  'query-params': {
    title: 'Query Parameters & Filtering',
    subtitle: 'Extract optional, default, and typed query parameters like FastAPI.',
    content: `
Query parameters are key-value pairs appended to the URL after a \`?\` mark (for example, \`/items?limit=20&search=keyboard&min_price=10.50\`).

In Zest, query parameters are easily extracted from \`req\` with zero boilerplate:

### Core API Methods
- \`req.queryParam("key")\`: Returns \`?[]const u8\` (or \`null\` if omitted from the URL).
- **Providing defaults**: Combine with Zig's \`orelse\` expression:
  \`\`\`zig
  const search = req.queryParam("search") orelse "";
  \`\`\`
- **Parsing integers with fallbacks**:
  \`\`\`zig
  const limit = if (req.queryParam("limit")) |l| (std.fmt.parseInt(usize, l, 10) catch 20) else 20;
  const page = if (req.queryParam("page")) |p| (std.fmt.parseInt(usize, p, 10) catch 1) else 1;
  \`\`\`
- **Parsing boolean flags**:
  \`\`\`zig
  const show_archived = if (req.queryParam("archived")) |val|
      std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1")
  else
      false;
  \`\`\`
    `,
    codeExamples: [
      {
        title: 'Complete Search & Paginated Filter Handler',
        language: 'zig',
        code: `fn listProducts(req: *zest.Request, res: *zest.Response) !void {
    // 1. Extract query params with fallbacks
    const limit = if (req.queryParam("limit")) |l|
        (std.fmt.parseInt(usize, l, 10) catch 25)
    else
        25;

    const offset = if (req.queryParam("offset")) |o|
        (std.fmt.parseInt(usize, o, 10) catch 0)
    else
        0;

    // 2. Build fluent filtered query
    var q = Product.model.query(&database.db, req.allocator)
        .limit(limit)
        .offset(offset);

    if (req.queryParam("search")) |s| {
        _ = q.where("name", .contains, s);
    }

    if (req.queryParam("min_price")) |mp| {
        if (std.fmt.parseFloat(f64, mp) catch null) |_| {
            _ = q.where("price", .gte, mp);
        }
    }

    // 3. Execute and stream JSON results
    const results = try q.exec();
    defer {
        for (results) |*p| p.deinit();
        req.allocator.free(results);
    }
    try res.json(results);
}`
      }
    ]
  },

  'sub-routers': {
    title: 'Sub-Router Route Groups',
    subtitle: 'Organize modular endpoints and API versioning with app.group.',
    content: `
Group routes under common prefixes (e.g. \`/api/v1\`, \`/auth\`, \`/admin\`). Groups can be nested infinitely and passed to external registrar modules.
    `,
    codeExamples: [
      {
        title: 'Mounting Route Groups',
        language: 'zig',
        code: `var api = app.group("/api/v1");

var items_group = try api.group("/items");
try items_group.get("", listItems);
try items_group.post("", createItem);
try items_group.get("/:id", getItem);

var auth_group = try api.group("/auth");
try auth_group.post("/login", loginHandler);
try auth_group.post("/register", registerHandler);`
      }
    ]
  },

  'request-response': {
    title: 'Request & Response API',
    subtitle: 'Streamlined primitives for reading inputs and constructing responses.',
    content: `
### Request Methods
- \`req.header(name)\`: Lookup request header case-insensitively.
- \`req.param(name)\`: Extract path parameter.
- \`req.queryParam(name)\`: Extract query parameter.
- \`req.json(T)\`: Deserialize request JSON body into struct \`T\`.
- \`req.validateJson(T, res)\`: Validate body against model rules, auto-responds with 422 on failure.
- \`req.multipart()\`: Parse multipart/form-data with file upload extractors.
- \`req.addBackgroundTask(fn, ctx)\`: Schedule background tasks.

### Response Methods
- \`res.json(val)\`: Write JSON response from any Zig struct, model, slice, or raw JSON string.
- \`res.status(code, val)\`: Set HTTP status code (e.g. \`.created\`, \`.not_found\`) and serialize Zig struct or string.
- \`res.err(code, message)\`: Send standardized error JSON \`{"error":"..."}\` with status code.
- \`res.badRequest(val)\`, \`res.notFound(val)\`, \`res.created(val)\`: Status convenience helpers.
- \`res.setHeader(name, val)\`: Add custom HTTP response header.
- \`res.setCookie(name, val, opts)\`: Issue HTTP cookies.
    `,
    codeExamples: []
  },

  'response-status': {
    title: 'Response Status & Formatting',
    subtitle: 'Send custom status codes, structured JSON, HTML, and redirects.',
    content: `
Zest response objects (\`*zest.Response\`) provide high-level methods for formatting any HTTP response cleanly.

### Standard HTTP Status Codes
Zest leverages Zig's native \`std.http.Status\` enum for compile-time validated status codes:
- \`.ok\` (200)
- \`.created\` (201)
- \`.accepted\` (202)
- \`.no_content\` (204)
- \`.bad_request\` (400)
- \`.unauthorized\` (401)
- \`.forbidden\` (403)
- \`.not_found\` (404)
- \`.conflict\` (409)
- \`.unprocessable_entity\` (422)
- \`.internal_server_error\` (500)

### Primary Response Helpers
- \`res.json(val)\`: Automatically serializes any Zig struct, array, slice, Model instance, or raw JSON string into an HTTP 200 JSON response.
- \`res.status(status, val)\`: Responds with custom HTTP status code and serializes any Zig struct/object to JSON (or sends raw string).
- \`res.err(status, message)\`: Sends an error JSON object \`{"error": "..."}\` with the specified status code.
- \`res.created(val)\`, \`res.badRequest(val)\`, \`res.notFound(val)\`: Semantic HTTP status helpers.
- \`res.text(plain_text)\`: Responds with \`text/plain\`.
- \`res.html("<h1>Hello</h1>")\`: Responds with \`text/html\`.
- \`res.redirect("/login")\`: Sends HTTP 302 Found redirect with \`Location\` header.
    `,
    codeExamples: [
      {
        title: 'Response Status Examples',
        language: 'zig',
        code: `// 201 Created with Zig struct literal
try res.status(.created, .{ .status = "created", .id = 101 });

// Error response helper
try res.err(.bad_request, "Invalid input payload");

// 204 No Content
try res.send("", .{ .status = .no_content });

// HTML rendering
try res.html("<!DOCTYPE html><html><body><h1>Welcome to Zest!</h1></body></html>");

// HTTP 302 Redirect
try res.redirect("/dashboard");`
      }
    ]
  },

  'error-handling': {
    title: 'Error Handling & HTTP Exceptions',
    subtitle: 'Standardized error responses, validation errors, and custom exception patterns.',
    content: `
Consistent, structured error payloads make frontends and API clients dramatically easier to build and debug.

### Standardized Error Format
Like FastAPI, Zest recommends returning error payloads with a clear top-level structure:

\`\`\`json
{
  "error": "Resource not found",
  "status": 404
}
\`\`\`

Or for validation errors, an array of faulty fields:
\`\`\`json
{
  "detail": [
    { "field": "email", "message": "Field 'email' must be a valid email address" }
  ]
}
\`\`\`

### Writing Expressive Controller Responses
With Zest's object responses and \`res.err(...)\`, returning errors is clean with zero manual allocations or string formatting:
    `,
    codeExamples: [
      {
        title: 'Clean Error Responses',
        language: 'zig',
        code: `pub fn getOrder(req: *zest.Request, res: *zest.Response) !void {
    const order_id = req.paramInt("id", u32) orelse {
        return res.err(.bad_request, "Invalid order ID");
    };

    var found = try Order.model.find(&database.db, req.allocator, order_id);
    if (found) |*ord| {
        defer ord.deinit();
        try res.json(ord.value);
    } else {
        return res.err(.not_found, "Order not found");
    }
}`
      }
    ]
  },

  'headers-cookies': {
    title: 'Headers & HTTP Cookies',
    subtitle: 'Inspect incoming headers, set custom headers, and manage secure HTTP cookies.',
    content: `
Zest provides first-class support for inspecting request headers and issuing secure, encrypted HTTP cookies.

### 1. Reading Request Headers
Look up any HTTP request header with case-insensitive matching:
\`\`\`zig
const auth_header = req.header("authorization");
const user_agent = req.header("user-agent") orelse "unknown";
const api_key = req.header("x-api-key");
\`\`\`

### 2. Setting Response Headers
Add custom headers to the outgoing response:
\`\`\`zig
try res.setHeader("X-Server", "Zest");
try res.setHeader("Cache-Control", "no-store, max-age=0");
\`\`\`

### 3. Managing HTTP Cookies (\`zest.Cookie\`)
Issue modern, security-hardened cookies with attributes like \`HttpOnly\`, \`Secure\`, \`SameSite\`, and expiration:
    `,
    codeExamples: [
      {
        title: 'Issuing and Clearing Cookies',
        language: 'zig',
        code: `// Setting a secure session cookie
try res.setCookie(.{
    .name = "session_token",
    .value = "xyz_jwt_token_secret_123",
    .path = "/",
    .http_only = true,      // Prevents JavaScript XSS access
    .secure = true,         // Enforces HTTPS transmission
    .same_site = .strict,   // Mitigates CSRF attacks
    .max_age = 86400,       // 24 hours
});

// Clearing a cookie on logout:
try res.setCookie(.{
    .name = "session_token",
    .value = "",
    .path = "/",
    .max_age = 0,           // Expires immediately
});`
      }
    ]
  },

  'middleware': {
    title: 'Middlewares & Logging',
    subtitle: 'Interceptor pipeline with ANSI colored metrics and CORS protection.',
    content: `
Middlewares execute before matching route handlers. Zest includes built-in middlewares:
- \`zest.middleware.logger\`: ANSI colored method, path, HTTP status, and microsecond response time.
- \`zest.middleware.cors(opts)\`: Cross-Origin Resource Sharing headers with preflight \`OPTIONS\` support.
    `,
    codeExamples: [
      {
        title: 'Configuring Global Middleware',
        language: 'zig',
        code: `// Terminal logger with execution time in microseconds
try app.use(zest.middleware.logger);

// CORS middleware allowing origins and methods
try app.use(zest.middleware.cors(.{
    .origins = "*",
    .methods = "GET, POST, PUT, DELETE, OPTIONS",
    .headers = "Content-Type, Authorization",
}));`
      }
    ]
  },

  'db-architecture': {
    title: 'Universal Database Architecture',
    subtitle: 'One model codebase targeting SQLite, PostgreSQL, or MongoDB.',
    content: `
Zest features a unified database driver abstraction. When your application calls \`zest.Db.connect(allocator, url)\`, Zest inspects the URL scheme and initializes the appropriate physical driver:

- \`sqlite:data.db\`: Real physical SQLite 3 database file with table schema creation.
- \`postgresql://...\`: PostgreSQL driver using native \`libpq\` with connection pooling.
- \`mongodb://...\`: MongoDB document collection database.
    `,
    codeExamples: [
      {
        title: 'Universal Connection Example',
        language: 'zig',
        code: `// Connecting via .env
const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:app.db");
var db = try zest.Db.connect(allocator, db_url);
defer db.deinit();`
      }
    ]
  },

  'sqlite-driver': {
    title: 'Real SQLite Persistence & WAL Mode',
    subtitle: 'Production-ready SQLite3 engine with Write-Ahead Logging (WAL) and automatic DDL schema synchronization.',
    content: `
Unlike mock or in-memory databases, Zest creates real physical SQLite 3 database files verified with standard \`SQLite format 3\` headers.

### Production SQLite Features in Zest
- **SQLite3 Open v2 Flags**: Opened using \`SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE\` to ensure robust multi-threaded file creation and access.
- **Automatic WAL Mode**: Automatically activates Write-Ahead Logging (\`PRAGMA journal_mode=WAL;\`) upon connection. Readers never block writers, and writers never block readers, offering high concurrent throughput.
- **Automated DDL Schema Sync**: On model save or query, table schemas are created automatically with strongly-typed columns and indexes.
- **Zero-Config File Management**: Supply any relative or absolute file path via \`sqlite:storage/app.db\` or \`DATABASE_URL=sqlite:products.db\`.
    `,
    codeExamples: [
      {
        title: 'Connecting to SQLite with WAL Mode',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Connects with sqlite3_open_v2 and enables PRAGMA journal_mode=WAL;
    var db = try zest.Db.connect(allocator, "sqlite:products.db");
    defer db.deinit();

    // Direct CRUD operations with Zig struct
    try db.insert("products", "prod_1", .{ .name = "MacBook Pro", .price = 1999.99 });
    const product_json = try db.findByIdAlloc("products", "prod_1", allocator);
    if (product_json) |json| {
        defer allocator.free(json);
        std.log.info("Loaded product: {s}", .{json});
    }
}`
      }
    ]
  },

  'postgres-driver': {
    title: 'PostgreSQL & Supabase',
    subtitle: 'Native libpq integration for production relational databases.',
    content: `
Connect directly to local PostgreSQL, AWS RDS, or Supabase connection poolers using standard connection strings with SSL mode enforcement:

\`\`\`env
DATABASE_URL=postgresql://postgres.test:secret@aws-0-us-east-1.pooler.supabase.com:6543/postgres?sslmode=require
\`\`\`
    `,
    codeExamples: []
  },

  'mongo-driver': {
    title: 'MongoDB Document Engine',
    subtitle: 'NoSQL document store support from the same ORM model interface.',
    content: `
Provide a standard \`mongodb://\` URL to route models to MongoDB collections seamlessly:
\`\`\`env
DATABASE_URL=mongodb://admin:secret@127.0.0.1:27017/analytics?authSource=admin
\`\`\`
    `,
    codeExamples: []
  },

  'db-pooling': {
    title: 'Connection Pooling (DbPool)',
    subtitle: 'Zero-allocation thread-safe connection pooling for high concurrency.',
    content: `
In high-throughput environments, \`DbPool\` manages an array of pre-connected database handles. Connections are locked and released using low-overhead spinlocks (\`std.atomic.Mutex\`):

\`\`\`zig
var pool = try zest.DbPool.init(allocator, "sqlite:app.db", 10);
defer pool.deinit();

// Acquire connection from pool
var conn = try pool.acquire();
defer pool.release(conn);

// Perform operations with conn.db...
\`\`\`
    `,
    codeExamples: []
  },

  'model-mixin': {
    title: 'Model Mixin & DDL Sync',
    subtitle: 'Compile-time ORM metadata generation, UUID auto-generation, schema sync, and full CRUD operations.',
    content: `
Any Zig struct becomes a full-featured database Model across SQLite, PostgreSQL, and MongoDB by declaring:
\`\`\`zig
pub const model = zest.Model(@This());
\`\`\`

### Primary Keys & Auto-Generation
- **UUID Primary Keys**: Declare \`id: ?[]const u8 = null\` (or \`[]const u8\`). When \`Model.save(&db, allocator, &instance)\` is invoked, Zest automatically generates an RFC 4122 UUID v4 if \`id\` is \`null\` or empty.
- **Integer IDs**: Declare \`id: u32\` or \`id: ?u32\` for traditional integer primary keys.
- **Auto-Syncing Table DDL**: \`Model.sync(&db)\` or initial \`Model.save()\` automatically generates and executes \`CREATE TABLE IF NOT EXISTS\` with mapped column types (\`INTEGER\`, \`REAL\`, \`BOOLEAN\`, \`TEXT\`).

### Injected Model Capabilities
- \`Model.save(&db, allocator, &instance)\`: Persists (insert or update) an instance to the database. Auto-populates UUID if missing.
- \`Model.find(&db, allocator, id)\`: Finds a single record by primary key (UUID string or integer ID). Returns \`!?std.json.Parsed(Self)\`.
- \`Model.findAll(&db, allocator)\`: Loads all raw JSON records for this table/collection.
- \`Model.delete(&db, id)\`: Deletes record by primary key. Returns \`bool\`.
- \`Model.count(&db)\`: Returns the total record count.
- \`Model.query(&db, allocator)\`: Instantiates a fluent \`QueryBuilder(Self)\` for chaining \`where\`, \`orderBy\`, \`limit\`, and \`offset\`.
- \`Model.toJson(&instance, allocator)\`: Serializes model instance to JSON.
- \`Model.fromJson(allocator, json_str)\`: Deserializes JSON string to \`std.json.Parsed(Self)\`.
- \`Model.hasMany(instance, TargetModel, foreign_key, &db, allocator)\`: Resolves one-to-many related records.
    `,
    codeExamples: [
      {
        title: 'Model with UUID Primary Key & Validation',
        language: 'zig',
        code: `const zest = @import("zest");

pub const Product = struct {
    id: ?[]const u8 = null, // Auto-generated UUIDv4 if null on save
    name: []const u8,
    price: f64,

    // Universal Comptime ORM Mixin
    pub const model = zest.Model(@This());

    // Automated FastAPI-grade Schema Validation
    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 3);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};`
      },
      {
        title: 'Saving and Querying Models',
        language: 'zig',
        code: `// 1. Save with automatic UUID generation
var product = Product{ .name = "Wireless Keyboard", .price = 89.99 };
try Product.model.save(&db, allocator, &product);

// 2. Find by UUID string
var found = try Product.model.find(&db, allocator, "c9bf9e57-1685-4c89-bafb-ff5af830be8a");
if (found) |*p| {
    defer p.deinit();
    std.log.info("Product: {s} - \${d:.2}", .{p.value.name, p.value.price});
}

// 3. Query with QueryBuilder
var q = Product.model.query(&db, allocator);
_ = q.where("price", .gte, 50.0);
const results = try q.exec();
defer {
    for (results) |*r| r.deinit();
    allocator.free(results);
}`
      }
    ]
  },

  'query-builder': {
    title: 'Fluent QueryBuilder',
    subtitle: 'Type-safe SQL & NoSQL query filtering and pagination.',
    content: `
Construct expressive queries that compile and execute identically across SQLite, PostgreSQL, and MongoDB:

- \`.where("field", .eq, value)\`
- \`.where("field", .neq, value)\`
- \`.where("field", .gt, value)\` / \`.gte\`
- \`.where("field", .lt, value)\` / \`.lte\`
- \`.where("field", .contains, substring)\`
- \`.orderBy("field", .asc | .desc)\`
- \`.limit(n)\` / \`.offset(n)\`
- \`.exec()\`: Returns array of parsed struct instances.
- \`.execJson()\`: Returns raw JSON strings.
    `,
    codeExamples: [
      {
        title: 'Complex Query Construction',
        language: 'zig',
        code: `const active_items = try Item.model.query(&db, allocator)
    .where("price", .gte, 5.0)
    .where("name", .contains, "Pro")
    .orderBy("price", .desc)
    .limit(20)
    .offset(0)
    .exec();

defer {
    for (active_items) |*item| item.deinit();
    allocator.free(active_items);
}`
      }
    ]
  },

  'relationships': {
    title: 'Model Relationships (hasMany & belongsTo)',
    subtitle: 'Declare and traverse associations between parent and child models.',
    content: `
Zest provides automated foreign key relationship mapping across both relational databases and document stores:

### 1. hasMany
Loads all child records where \`TargetModel.<foreign_key> == parent.id\`:
\`\`\`zig
const posts = try User.model.hasMany(&user, Post, "user_id", &db, allocator);
defer {
    for (posts) |*p| p.deinit();
    allocator.free(posts);
}
\`\`\`

### 2. belongsTo
Fetches the single parent record where \`ParentModel.id == child.<foreign_key>\`:
\`\`\`zig
var author = try Post.model.belongsTo(&post, User, "user_id", &db, allocator);
if (author) |*a| {
    defer a.deinit();
    std.log.info("Author: {s}", .{a.value.username});
}
\`\`\`
    `,
    codeExamples: []
  },

  'validation': {
    title: 'FastAPI-Style Validation & HTTP 422',
    subtitle: 'Declarative struct validation with formatted error responses.',
    content: `
Add a \`validate\` method to your struct. When \`req.validateJson(Model, res)\` is called, Zest parses the body and executes the validation rules. If validation fails, Zest immediately halts execution, sets status to **422 Unprocessable Entity**, and returns a structured JSON error response:

\`\`\`json
{
  "detail": [
    { "field": "name", "message": "Field 'name' must be at least 3 characters" },
    { "field": "email", "message": "Field 'email' must be a valid email address" }
  ]
}
\`\`\`
    `,
    codeExamples: [
      {
        title: 'Implementing Validation Rules',
        language: 'zig',
        code: `const RegisterInput = struct {
    name: []const u8,
    email: []const u8,
    age: u8,

    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "name", self.name, 3);
        zest.validator.requireEmail(errs, "email", self.email);
        zest.validator.requireRange(errs, "age", self.age, 18, 120);
    }
};

fn handleRegister(req: *zest.Request, res: *zest.Response) !void {
    // Returns null and automatically sends 422 JSON if validation fails
    var parsed = (try req.validateJson(RegisterInput, res)) orelse return;
    defer parsed.deinit();

    try res.status(.created, .{ .status = "registered" });
}`
      }
    ]
  },

  'background-tasks': {
    title: 'FastAPI-Style Background Tasks',
    subtitle: 'Queue asynchronous work outside of the HTTP response lifecycle.',
    content: `
Schedule tasks (e.g. sending emails, writing audit logs, syncing webhooks) without blocking the client. The client receives the HTTP response immediately, and the task executes immediately following response completion:

\`\`\`zig
fn handleCheckout(req: *zest.Request, res: *zest.Response) !void {
    // 1. Respond to client immediately
    try res.json(.{ .order_id = 42, .status = "paid" });

    // 2. Schedule non-blocking background task
    const sendConfirmation = struct {
        fn run(ctx: ?*anyopaque) void {
            _ = ctx;
            std.log.info("[Task] Sent customer invoice and notified warehouse", .{});
        }
    }.run;

    try req.addBackgroundTask(sendConfirmation, null);
}
\`\`\`
    `,
    codeExamples: []
  },

  'multipart-uploads': {
    title: 'Multipart Form Data & File Uploads',
    subtitle: 'Streaming multipart parser with direct-to-disk file saving.',
    content: `
Handle file uploads and form inputs with \`req.multipart()\`. Extract text fields with \`form.get(name)\` and files with \`form.getFile(name)\`:

\`\`\`zig
fn uploadAvatar(req: *zest.Request, res: *zest.Response) !void {
    var form = try req.multipart();
    defer form.deinit();

    const username = form.get("username") orelse "anonymous";

    if (form.getFile("avatar")) |file| {
        // Direct C fwrite stream to disk
        try file.saveTo(req.allocator, "./uploads/avatar.png");
    }

    try res.json(.{ .status = "uploaded" });
}
\`\`\`
    `,
    codeExamples: []
  },

  'openapi-swagger': {
    title: 'Swagger UI & OpenAPI 3.0',
    subtitle: 'Zero-configuration interactive Swagger UI documentation and compile-time OpenAPI 3.0 schema generation.',
    content: `
Zest delivers automated, zero-overhead API documentation out of the box. Simply calling \`app.enableDocs()\` activates:

- **Interactive Swagger UI** served at \`/docs\` with one-click **"Try it out"** live testing and request duration timing.
- **OpenAPI 3.0.0 JSON Specification** served at \`/openapi.json\` compliant with OpenAPI, Postman, and client SDK generators.
- **Automatic Route Deduplication**: Automatically normalizes trailing slashes (e.g. \`/products/\` and \`/products\`) so routes never appear as duplicates.
- **Model Reflection via \`app.registerModel(T)\`**: Comptime struct inspection that automatically derives OpenAPI types, required fields, and nullable attributes.

---

### Key Features

1. **Model Registration (\`app.registerModel(T)\`)**:
   Pass your Model struct directly to \`app.registerModel(Product)\`. Zest inspects the struct at compile time and creates accurate schemas under \`components.schemas\`:
   - Integers (\`u32\`, \`i64\`) -> \`{"type": "integer"}\`
   - Floats (\`f64\`, \`f32\`) -> \`{"type": "number"}\`
   - Booleans (\`bool\`) -> \`{"type": "boolean"}\`
   - Strings (\`[]const u8\`) -> \`{"type": "string"}\`
   - Optionals (\`?T\`) -> \`{"nullable": true}\` and excluded from \`"required"\` array.
   - Non-optionals -> Added to \`"required": ["name", "price"]\`.

2. **Collection vs Entity Responses**:
   - Collection endpoints (e.g. \`GET /api/v1/products\`) automatically render response schemas as typed arrays:
     \`\`\`json
     { "type": "array", "items": { "$ref": "#/components/schemas/Product" } }
     \`\`\`
   - Single item endpoints (e.g. \`GET /api/v1/products/:id\`) reference the single schema \`{"$ref": "#/components/schemas/Product"}\`.

3. **Intelligent Path Parameters**:
   Parameters like \`:id\` are automatically recognized with interactive input fields in Swagger UI, typed according to the model's primary key (integer or string/UUID).
    `,
    codeExamples: [
      {
        title: 'Enabling Swagger UI & Registering Models',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");
const Product = @import("models/product.zig").Product;

pub fn main() !void {
    var app = zest.init("127.0.0.1", 8000);
    defer app.deinit();

    // Serves Swagger UI at /docs and spec at /openapi.json
    app.enableDocs();

    // Register Model schema for Swagger UI with comptime type reflection
    try app.registerModel(Product);

    // Register routes
    try app.get("/api/v1/products", listProducts);
    try app.get("/api/v1/products/:id", getProduct);
    try app.post("/api/v1/products", createProduct);
    try app.delete("/api/v1/products/:id", deleteProduct);

    std.log.info("Swagger UI available at: http://127.0.0.1:8000/docs", .{});
    try app.listen();
}`
      },
      {
        title: 'Customizing Documentation Metadata',
        language: 'zig',
        code: `// Customize endpoint URLs and API branding
app.enableDocsCustom(
    "/api/documentation",    // Custom Swagger UI path
    "/api/v1/openapi.json",  // Custom OpenAPI spec path
    "E-Commerce Cloud API",  // API Title
    "2.4.0",                 // API Version
    "Production API for order processing and inventory management" // Description
);`
      },
      {
        title: 'Accessing Raw OpenAPI Specification',
        language: 'bash',
        code: `# Inspect the raw OpenAPI 3.0 JSON specification
curl -s http://127.0.0.1:8000/openapi.json | jq .

# Generate TypeScript client or SDK using openapi-generator
npx @openapitools/openapi-generator-cli generate \\
  -i http://127.0.0.1:8000/openapi.json \\
  -g typescript-axios \\
  -o ./client-sdk`
      }
    ]
  },

  'uuid-generator': {
    title: 'UUID v4 Engine (zuuid)',
    subtitle: 'Zero-allocation RFC 4122 Version 4 UUID generation and validation.',
    content: `
Zest includes a high-performance UUID engine available under both \`zest.uuid\` and \`zest.zuuid\`.

On Linux, UUIDs are generated with cryptographically secure random bytes via direct \`getrandom()\` syscalls with zero heap allocation. On other platforms, high-resolution nanosecond bit-mixing provides high-entropy random identifiers.

### Available Functions
- \`zuuid.generate() -> [36]u8\`: Generates a random RFC 4122 v4 UUID string returned as a stack value (36-byte array). Easily coerced to \`[]const u8\`.
- \`zuuid.v4(buf: *[36]u8) -> []const u8\`: Formats a UUID v4 directly into your stack buffer. Zero allocations.
- \`zuuid.new(allocator) -> ![]u8\`: Allocates and returns a fresh owned UUID string.
- \`zuuid.generateAlloc(allocator) -> ![]u8\`: Alias for \`zuuid.new\`.
- \`zuuid.isValid(str: []const u8) -> bool\`: Validates whether a given string is a valid 36-character hyphenated UUID.

### Auto-UUID in Models
When declaring a model with an optional string ID (\`id: ?[]const u8 = null\`), calling \`Model.save(&db, allocator, &instance)\` will **automatically generate** a fresh UUID v4 if the ID is \`null\` or empty.
    `,
    codeExamples: [
      {
        title: 'Generating and Validating UUIDs',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // 1. Stack value generation (36-byte array)
    const id_arr = zest.zuuid.generate();
    std.log.info("Generated UUID: {s}", .{id_arr});

    // 2. Format into stack buffer (zero allocation)
    var buf: [36]u8 = undefined;
    const id_slice = zest.zuuid.v4(&buf);
    std.log.info("Buffer UUID: {s}", .{id_slice});

    // 3. Heap-allocated UUID string
    const owned_id = try zest.zuuid.new(allocator);
    defer allocator.free(owned_id);
    std.log.info("Allocated UUID: {s}", .{owned_id});

    // 4. Validate UUID format
    const is_valid = zest.zuuid.isValid(id_slice);
    std.log.info("Is valid UUID? {any}", .{is_valid}); // true
}`
      },
      {
        title: 'Using Auto-UUID in Models & Controllers',
        language: 'zig',
        code: `const Product = struct {
    id: ?[]const u8 = null, // Auto-generated UUIDv4 on save if null
    name: []const u8,
    price: f64,

    pub const model = zest.Model(@This());
};

fn createProduct(req: *zest.Request, res: *zest.Response) !void {
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    var product = parsed.value;
    // If not supplied in payload, zest.zuuid.new or auto-save generates it:
    if (product.id == null or product.id.?.len == 0) {
        product.id = try zest.zuuid.new(req.allocator);
    }

    try Product.model.save(&db, req.allocator, &product);
    try res.status(.created, .{ .status = "created" });
}`
      }
    ]
  },

  'time-datetime': {
    title: 'Time & DateTime (zest.time)',
    subtitle: 'High-precision timestamps, ISO-8601 formatting, HTTP-date generation, and calendar conversion.',
    content: `
Zest provides a dedicated \`zest.time\` module designed for web servers, caching headers, timestamps, and benchmarking.

### Timestamps & Monotonic Clocks
- \`time.now() -> i64\`: Returns current Unix epoch time in seconds.
- \`time.milliTimestamp() -> i64\`: Returns current Unix epoch time in milliseconds.
- \`time.nanoTimestamp() -> i128\`: Returns current Unix epoch time in nanoseconds.
- \`time.getMonotonicNanos() -> i128\`: Monotonic clock for sub-microsecond latency measurement and middleware timing.

### Calendar & DateTime Struct (\`time.DateTime\`)
The \`DateTime\` struct provides calendar conversion from Unix seconds without external C dependencies:
- \`DateTime.nowUtc()\`: Returns current UTC calendar struct (\`year\`, \`month\`, \`day\`, \`hour\`, \`minute\`, \`second\`, \`weekday\`).
- \`DateTime.fromEpoch(secs)\`: Converts any Unix timestamp into a \`DateTime\`.
- \`dt.toIso8601(buf)\`: Formats as standard ISO-8601 / RFC 3339 UTC (\`2026-10-01T20:44:26Z\`).
- \`dt.toHttpDate(buf)\`: Formats as RFC 7231 / RFC 1123 HTTP date (\`Thu, 01 Oct 2026 20:44:26 GMT\`), perfect for \`Last-Modified\`, \`Date\`, and \`Expires\` headers.
- \`dt.toDateString(buf)\`: Formats as \`YYYY-MM-DD\`.
- \`dt.toTimeString(buf)\`: Formats as \`HH:MM:SS\`.

### Direct String Helpers
- \`time.iso8601(&buf) -> []const u8\`: Fast current ISO-8601 string.
- \`time.httpDate(&buf) -> []const u8\`: Fast current HTTP-date string.
- \`time.date(&buf) -> []const u8\`: Fast current \`YYYY-MM-DD\` string.
- \`time.timeOfDay(&buf) -> []const u8\`: Fast current \`HH:MM:SS\` string.
- \`time.parseIso8601(str) -> ?DateTime\`: Parses ISO-8601 strings into a \`DateTime\` struct.
    `,
    codeExamples: [
      {
        title: 'Working with Timestamps & ISO-8601',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

pub fn main() !void {
    // 1. Current Unix timestamps
    const sec = zest.time.now();
    const ms = zest.time.milliTimestamp();
    std.log.info("Unix seconds: {d}, ms: {d}", .{sec, ms});

    // 2. High-precision latency timing
    const t0 = zest.time.getMonotonicNanos();
    // ... perform work ...
    const elapsed_ns = zest.time.getMonotonicNanos() - t0;
    std.log.info("Elapsed: {d} ns ({d:.2} ms)", .{elapsed_ns, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0});

    // 3. Current ISO-8601 string (e.g. "2026-10-01T20:44:26Z")
    var iso_buf: [32]u8 = undefined;
    const iso_str = zest.time.iso8601(&iso_buf);
    std.log.info("ISO-8601: {s}", .{iso_str});

    // 4. HTTP-date for response headers (e.g. "Thu, 01 Oct 2026 20:44:26 GMT")
    var http_buf: [32]u8 = undefined;
    const http_str = zest.time.httpDate(&http_buf);
    std.log.info("HTTP Date: {s}", .{http_str});
}`
      },
      {
        title: 'Parsing Dates and Measuring Request Latency',
        language: 'zig',
        code: `// Parse incoming ISO-8601 string from request payload or query parameter
if (zest.time.parseIso8601("2026-10-01T15:30:00Z")) |dt| {
    std.log.info("Parsed Year: {d}, Month: {d}, Day: {d}", .{dt.year, dt.month, dt.day});
}

// In a custom timing middleware:
fn timingMiddleware(req: *zest.Request, res: *zest.Response) !bool {
    var date_buf: [32]u8 = undefined;
    res.setHeader("Date", zest.time.httpDate(&date_buf));
    return true;
}`
      }
    ]
  },

  'zenv-loader': {
    title: 'Environment Variables (zenv)',
    subtitle: 'Python-like .env loader supporting comments, quotes, and type casting.',
    content: `
Zest includes its own standalone environment loader called \`zenv\` that parses \`.env\` files with Python \`python-dotenv\` parity:

- \`zenv.get("KEY")\`: Returns \`?[]const u8\`.
- \`zenv.getInt("PORT", u16)\`: Parses integers.
- \`zenv.getBool("DEBUG")\`: Evaluates boolean flags (\`true\`, \`yes\`, \`1\`).
- \`zenv.getOr("KEY", "fallback")\`: Fallback default values.
    `,
    codeExamples: [
      {
        title: 'Loading .env configuration',
        language: 'zig',
        code: `try zest.zenv.load(allocator);
defer zest.zenv.deinit();

const port = zest.zenv.getInt("PORT", u16) orelse 8000;
const debug = zest.zenv.getBool("DEBUG");
const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:app.db");`
      }
    ]
  },

  'jwt-security': {
    title: 'JWT Authentication & Security',
    subtitle: 'HMAC-SHA256 token generation and cryptographic validation.',
    content: `
Sign and verify JSON Web Tokens (\`HS256\`) with zero external dependencies:

\`\`\`zig
// Sign token with Zig struct or raw string
const token = try zest.jwt.sign(allocator, .{ .sub = "usr_123", .role = "admin" }, "secret_key_123");
defer allocator.free(token);

// Verify and decode token
const payload = try zest.jwt.verify(allocator, token, "secret_key_123");
defer allocator.free(payload);
std.log.info("Validated claims: {s}", .{payload});

// Or decode directly into typed struct:
const Claims = struct { sub: []const u8, role: []const u8 };
const parsed = try zest.jwt.verifyAs(Claims, allocator, token, "secret_key_123");
defer parsed.deinit();
\`\`\`
    `,
    codeExamples: []
  },

  'auth-middleware': {
    title: 'Route Guards & Role-Based Auth',
    subtitle: 'Protect endpoints and sub-router groups with JWT verification.',
    content: `
Secure your API by combining Zest's high-speed HS256 JWT cryptography with custom route guard handlers.

### Authentication Flow
1. Client sends token in the \`Authorization: Bearer <token>\` header.
2. The route handler or guard extracts the token slice.
3. \`zest.jwt.verify\` validates the cryptographic signature and token expiry.
4. If valid, the handler unpacks user claims (e.g. user ID and role).
5. If invalid or missing, respond with **HTTP 401 Unauthorized**.
    `,
    codeExamples: [
      {
        title: 'Protected Controller Handler',
        language: 'zig',
        code: `const JWT_SECRET = "super_secure_production_secret_key_123";

fn authenticateUser(req: *zest.Request, res: *zest.Response) !?[]const u8 {
    const auth_header = req.header("authorization") orelse {
        try res.status(.unauthorized, .{ .@"error" = "Missing Authorization header" });
        return null;
    };

    if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
        try res.status(.unauthorized, .{ .@"error" = "Invalid bearer token format" });
        return null;
    };

    const token = auth_header["Bearer ".len..];
    const claims_json = zest.jwt.verify(req.allocator, token, JWT_SECRET) catch {
        try res.status(.unauthorized, .{ .@"error" = "Invalid or expired token" });
        return null;
    };

    return claims_json;
}

// Protected route handler:
pub fn getProfile(req: *zest.Request, res: *zest.Response) !void {
    const claims = (try authenticateUser(req, res)) orelse return;
    defer req.allocator.free(claims);

    try res.json(claims);
}`
      }
    ]
  },

  'testing-guide': {
    title: 'Testing Guide & Test Cases',
    subtitle: 'Write robust unit and integration tests using Zig standard testing.',
    content: `
Because Zest is built with pure Zig and zero global state, testing models, validation, and route matching is fast, reliable, and runs entirely in parallel with \`zig build test\`.

### Testing Checklist
1. **Model Validation**: Ensure valid structs pass and invalid values trigger appropriate errors.
2. **Database Queries**: Test inserting and finding records with in-memory or temporary SQLite files.
3. **Route Matching**: Test path parameters and dynamic segment extraction.
    `,
    codeExamples: [
      {
        title: 'src/tests.zig (Example Test Suite)',
        language: 'zig',
        code: `const std = @import("std");
const testing = std.testing;
const zest = @import("zest");
const Product = @import("models/product.zig").Product;

test "Product validation rejects invalid prices" {
    var errs = zest.ValidationErrors.init(testing.allocator);
    defer errs.deinit();

    const bad_product = Product{
        .id = 1,
        .name = "A", // too short (min length 3)
        .price = -5.0, // invalid price
    };

    bad_product.validate(&errs);
    try testing.expect(errs.hasErrors());
    try testing.expectEqual(@as(usize, 2), errs.errors.items.len);
}

test "SQLite persistence and retrieval" {
    var db = try zest.Db.connect(testing.allocator, "sqlite:test_tmp.db");
    defer {
        db.deinit();
        _ = std.os.linux.unlink("test_tmp.db");
    }

    const item = Product{ .id = 42, .name = "Wireless Keyboard", .price = 69.99 };
    try Product.model.save(&db, testing.allocator, &item);

    var found = try Product.model.find(&db, testing.allocator, 42);
    try testing.expect(found != null);
    defer found.?.deinit();

    try testing.expectEqualStrings("Wireless Keyboard", found.?.value.name);
    try testing.expectEqual(@as(f64, 69.99), found.?.value.price);
}`
      }
    ]
  },

  'deployment-docker': {
    title: 'Production Deployment & Docker',
    subtitle: 'Optimized binary compilation, containerization, and reverse proxy setup.',
    content: `
Deploying a Zest application delivers exceptional throughput with minimal memory footprint (typically < 15MB RAM under heavy load).

---

### 1. Compiling for Production
Build a native stripped release binary using Zig's optimization flags:

\`\`\`bash
# ReleaseSafe: full optimizations with safety panics on undefined behavior
zig build -Doptimize=ReleaseSafe

# ReleaseFast: maximum optimization without runtime safety checks
zig build -Doptimize=ReleaseFast
\`\`\`

The compiled binary will be placed in \`zig-out/bin/\`.

---

### 2. Multi-Stage Dockerfile
Use this lightweight Dockerfile to compile and run your service inside an Alpine or Debian container:

\`\`\`dockerfile
# Stage 1: Build binary with Zig
FROM alpine:3.20 AS builder
RUN apk add --no-cache zig gcc musl-dev sqlite-dev postgresql-dev

WORKDIR /app
COPY . .
RUN zig build -Doptimize=ReleaseSafe

# Stage 2: Minimal runtime image
FROM alpine:3.20
RUN apk add --no-cache libsqlite3 libpq ca-certificates

WORKDIR /app
COPY --from=builder /app/zig-out/bin/* /app/server
COPY .env* ./

EXPOSE 8000
CMD ["/app/server"]
\`\`\`

---

### 3. Production Reverse Proxy (Caddy / Nginx)
Run Zest behind Caddy or Nginx for automated HTTPS certificates:

#### Caddyfile Example:
\`\`\`caddyfile
api.example.com {
    reverse_proxy 127.0.0.1:8000
}
\`\`\`
    `,
    codeExamples: [
      {
        title: 'Systemd Service Unit (/etc/systemd/system/zest.service)',
        language: 'ini',
        code: `[Unit]
Description=Zest Production API
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/my-zest-api
ExecStart=/var/www/my-zest-api/zig-out/bin/my-zest-api
Restart=always
RestartSec=3
Environment=PORT=8000 DATABASE_URL=sqlite:production.db

[Install]
WantedBy=multi-user.target`
      }
    ]
  }
};
