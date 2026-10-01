export const DOCS_SECTIONS = [
  {
    id: 'getting-started',
    title: 'Getting Started',
    items: [
      { id: 'introduction', title: 'Introduction' },
      { id: 'prerequisites', title: 'Prerequisites' },
      { id: 'installation', title: 'Installation' },
      { id: 'build-zig', title: 'Configuring build.zig' },
      { id: 'quickstart', title: 'Quickstart Tutorial' }
    ]
  },
  {
    id: 'routing-http',
    title: 'Routing & HTTP',
    items: [
      { id: 'router', title: 'Router & Route Handlers' },
      { id: 'path-params', title: 'Dynamic Path Parameters' },
      { id: 'sub-routers', title: 'Sub-Router Route Groups' },
      { id: 'request-response', title: 'Request & Response API' },
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
      { id: 'zenv-loader', title: 'Environment Loader (zenv)' },
      { id: 'jwt-security', title: 'JWT Authentication & Cookies' }
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
    try res.json("{\\"message\\": \\"Hello, Zest!\\"}");
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
    title: 'Package Installation',
    subtitle: 'Adding Zest to your project using the standard Zig package manager.',
    content: `
Zest integrates directly into Zig's native package manager. In your project root, execute the \`zig fetch\` command:

\`\`\`bash
zig fetch --save git+https://github.com/Alazar42/Zest.git
\`\`\`

This automatically computes the package cryptographic hash and registers Zest in your \`build.zig.zon\` dependencies manifest.
    `,
    codeExamples: [
      {
        title: 'Resulting build.zig.zon snippet',
        language: 'zig',
        code: `.{
    .name = .my_app,
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
    subtitle: 'Integrate Zest into any existing build script without restructuring your project.',
    content: `
Many developers already have a custom \`build.zig\` configured with compiler flags, targets, and assets. You **do not** need to replace your build script. You only need to add two specific lines:

### Step 1: Fetch the Dependency in build(b)
Add this line inside your \`pub fn build(b: *std.Build) void\` function:

\`\`\`zig
const zest_dep = b.dependency("zest", .{
    .target = target,
    .optimize = optimize,
});
\`\`\`

### Step 2: Import Zest into your Executable
Where your executable (\`exe\`) is defined, add the import to the root module:

\`\`\`zig
// If your project uses standard b.addExecutable:
exe.root_module.addImport("zest", zest_dep.module("zest"));
\`\`\`

*(Alternatively, if your build script defines modules via \`b.createModule\`)*:
\`\`\`zig
.imports = &.{
    .{ .name = "zest", .module = zest_dep.module("zest") },
},
\`\`\`
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

  'quickstart': {
    title: 'Quickstart Tutorial',
    subtitle: 'Build and run a complete RESTful service in 60 seconds.',
    content: `
Let's assemble a complete, production-ready REST API featuring models, validation, environment loading, and query filtering.
    `,
    codeExamples: [
      {
        title: 'src/main.zig',
        language: 'zig',
        code: `const std = @import("std");
const zest = @import("zest");

// 1. Define Model with automated validation and ORM mixin
const Product = struct {
    id: u32,
    title: []const u8,
    price: f64,

    pub const model = zest.Model(@This());

    pub fn validate(self: *const @This(), errs: *zest.ValidationErrors) void {
        zest.validator.requireMinLength(errs, "title", self.title, 3);
        zest.validator.requireMin(errs, "price", self.price, 0.01);
    }
};

var db: zest.Db = undefined;

// 2. Controller Handlers
fn listProducts(req: *zest.Request, res: *zest.Response) !void {
    var q = Product.model.query(&db, req.allocator);
    if (req.queryParam("search")) |s| {
        _ = q.where("title", .contains, s);
    }
    const products = try q.exec();
    defer {
        for (products) |*p| p.deinit();
        req.allocator.free(products);
    }
    try res.jsonValue(products);
}

fn createProduct(req: *zest.Request, res: *zest.Response) !void {
    // Automatically validates payload, responds with HTTP 422 if invalid
    var parsed = (try req.validateJson(Product, res)) orelse return;
    defer parsed.deinit();

    try Product.model.save(&db, req.allocator, &parsed.value);
    try res.status(.created, "{\\"status\\":\\"created\\"}");
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Load .env
    zest.zenv.load(gpa) catch {};
    defer zest.zenv.deinit();

    const db_url = zest.zenv.getOr("DATABASE_URL", "sqlite:products.db");
    const port = zest.zenv.getInt("PORT", u16) orelse 8000;

    // Initialize Database
    db = try zest.Db.connect(gpa, db_url);
    defer db.deinit();

    // Initialize Zest Application
    var app = zest.init("127.0.0.1", port);
    defer app.deinit();

    try app.use(zest.middleware.logger);
    try app.use(zest.middleware.cors(.{}));
    app.enableDocs(); // Swagger UI at /docs

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
        try res.json("{\\"status\\":\\"ok\\"}");
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
        try res.status(.bad_request, "{\\"error\\":\\"Invalid user ID\\"}");
        return;
    };

    const include_history = req.queryParam("history") != null;

    // Fetch user record...
    try res.json("{\\"user_id\\": 123}");
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
- \`res.json(payload)\`: Write JSON string with \`application/json\` header.
- \`res.jsonValue(val)\`: Serialize any Zig struct directly to JSON response.
- \`res.status(code, body)\`: Set HTTP status code (e.g. \`.created\`, \`.not_found\`).
- \`res.setHeader(name, val)\`: Add custom HTTP response header.
- \`res.setCookie(name, val, opts)\`: Issue HTTP cookies.
    `,
    codeExamples: []
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
    title: 'Real SQLite Persistence',
    subtitle: 'Physical disk storage with automated schema creation.',
    content: `
Unlike mock or memory-only databases, Zest creates real physical SQLite 3 database files verified with standard \`SQLite format 3\` headers. When saving models, table DDL is automatically generated and synchronized on first insert.
    `,
    codeExamples: [
      {
        title: 'SQLite Connection',
        language: 'zig',
        code: `var db = try zest.Db.connect(allocator, "sqlite:storage/app.db");
defer db.deinit();

// Direct CRUD operations
try db.insert("users", "usr_101", "{\\"name\\":\\"Alice\\",\\"role\\":\\"admin\\"}");
const user_json = try db.findByIdAlloc("users", "usr_101", allocator);`
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
    subtitle: 'Compile-time ORM metadata generation and schema management.',
    content: `
Any Zig struct can become a full-featured database Model by declaring \`pub const model = zest.Model(@This());\`.

### Injected Model Capabilities
- \`Model.save(&db, allocator, &instance)\`: Persists instance to database.
- \`Model.find(&db, allocator, id)\`: Finds single record by primary key.
- \`Model.findAll(&db, allocator)\`: Loads all records.
- \`Model.delete(&db, id)\`: Deletes record by primary key.
- \`Model.query(&db, allocator)\`: Instantiates fluent \`QueryBuilder\`.
- \`Model.sync(&db)\`: Automatically creates database table with typed columns.
    `,
    codeExamples: [
      {
        title: 'Declaring a Model',
        language: 'zig',
        code: `const User = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    is_active: bool = true,

    pub const model = zest.Model(@This());
};`
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

    try res.status(.created, "{\\"status\\":\\"registered\\"}");
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
    try res.status(.ok, "{\\"order_id\\": 42, \\"status\\": \\"paid\\"}");

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

    try res.json("{\\"status\\": \\"uploaded\\"}");
}
\`\`\`
    `,
    codeExamples: []
  },

  'openapi-swagger': {
    title: 'Swagger UI & OpenAPI 3.0',
    subtitle: 'Automated interactive documentation generation.',
    content: `
Call \`app.enableDocs()\` to automatically serve:
- Interactive Swagger UI at \`/docs\`
- Standard OpenAPI 3.0 JSON specification at \`/openapi.json\`

Customize titles, versions, and descriptions with \`app.enableDocsCustom(...)\`.
    `,
    codeExamples: [
      {
        title: 'Enabling OpenAPI Docs',
        language: 'zig',
        code: `var app = zest.init("127.0.0.1", 8000);
defer app.deinit();

// Enables Swagger UI at http://127.0.0.1:8000/docs
app.enableDocs();`
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
// Sign token
const token = try zest.jwt.sign(allocator, "{\\"sub\\":\\"usr_123\\",\\"role\\":\\"admin\\"}", "secret_key_123", 3600);
defer allocator.free(token);

// Verify and decode token
const payload = try zest.jwt.verify(allocator, token, "secret_key_123");
if (payload) |json_claims| {
    defer allocator.free(json_claims);
    std.log.info("Validated claims: {s}", .{json_claims});
}
\`\`\`
    `,
    codeExamples: []
  }
};
