const std = @import("std");

/// SQLite C API bindings
pub const sqlite = struct {
    pub const OK: c_int = 0;
    pub const ROW: c_int = 100;
    pub const DONE: c_int = 101;
    pub const OPEN_READONLY: c_int = 0x00000001;
    pub const OPEN_READWRITE: c_int = 0x00000002;
    pub const OPEN_CREATE: c_int = 0x00000004;

    pub extern "c" fn sqlite3_open(filename: [*:0]const u8, ppDb: *?*anyopaque) c_int;
    pub extern "c" fn sqlite3_open_v2(filename: [*:0]const u8, ppDb: *?*anyopaque, flags: c_int, zVfs: ?[*:0]const u8) c_int;
    pub extern "c" fn sqlite3_close(pDb: ?*anyopaque) c_int;
    pub extern "c" fn sqlite3_exec(
        pDb: ?*anyopaque,
        sql: [*:0]const u8,
        callback: ?*const fn (?*anyopaque, c_int, [*]?[*:0]u8, [*]?[*:0]u8) callconv(.c) c_int,
        arg: ?*anyopaque,
        errmsg: ?*?[*:0]u8,
    ) c_int;
    pub extern "c" fn sqlite3_prepare_v2(
        pDb: ?*anyopaque,
        zSql: [*:0]const u8,
        nByte: c_int,
        ppStmt: *?*anyopaque,
        pzTail: ?*?[*:0]const u8,
    ) c_int;
    pub extern "c" fn sqlite3_step(pStmt: ?*anyopaque) c_int;
    pub extern "c" fn sqlite3_column_text(pStmt: ?*anyopaque, iCol: c_int) ?[*:0]const u8;
    pub extern "c" fn sqlite3_column_bytes(pStmt: ?*anyopaque, iCol: c_int) c_int;
    pub extern "c" fn sqlite3_column_count(pStmt: ?*anyopaque) c_int;
    pub extern "c" fn sqlite3_finalize(pStmt: ?*anyopaque) c_int;
    pub extern "c" fn sqlite3_errmsg(pDb: ?*anyopaque) [*:0]const u8;
};

/// PostgreSQL libpq C API bindings
pub const pq = struct {
    pub const CONNECTION_OK: c_int = 0;
    pub const PGRES_COMMAND_OK: c_int = 1;
    pub const PGRES_TUPLES_OK: c_int = 2;

    pub extern "c" fn PQconnectdb(conninfo: [*:0]const u8) ?*anyopaque;
    pub extern "c" fn PQstatus(conn: ?*anyopaque) c_int;
    pub extern "c" fn PQerrorMessage(conn: ?*anyopaque) [*:0]const u8;
    pub extern "c" fn PQfinish(conn: ?*anyopaque) void;
    pub extern "c" fn PQexec(conn: ?*anyopaque, query: [*:0]const u8) ?*anyopaque;
    pub extern "c" fn PQresultStatus(res: ?*anyopaque) c_int;
    pub extern "c" fn PQresultErrorMessage(res: ?*anyopaque) [*:0]const u8;
    pub extern "c" fn PQntuples(res: ?*anyopaque) c_int;
    pub extern "c" fn PQnfields(res: ?*anyopaque) c_int;
    pub extern "c" fn PQfname(res: ?*anyopaque, field_num: c_int) ?[*:0]const u8;
    pub extern "c" fn PQgetvalue(res: ?*anyopaque, tup_num: c_int, field_num: c_int) ?[*:0]const u8;
    pub extern "c" fn PQclear(res: ?*anyopaque) void;
};

pub const DriverKind = enum {
    sqlite,
    postgres,
    mongodb,
};

/// MongoDB Client configuration and connection state
pub const MongoClient = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 27017,
    database: []const u8 = "zest",
    stream: ?std.Io.net.Stream = null,
    collections: std.StringHashMap(std.StringHashMap([]const u8)),

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, database: []const u8) MongoClient {
        return .{
            .host = host,
            .port = port,
            .database = database,
            .stream = null,
            .collections = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *MongoClient, allocator: std.mem.Allocator) void {
        var iter = self.collections.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            var doc_iter = entry.value_ptr.iterator();
            while (doc_iter.next()) |d| {
                allocator.free(d.key_ptr.*);
                allocator.free(d.value_ptr.*);
            }
            entry.value_ptr.deinit();
        }
        self.collections.deinit();
    }
};

allocator: std.mem.Allocator,
kind: DriverKind,
handle: ?*anyopaque = null, // sqlite3* or PGconn*
mongo_client: ?MongoClient = null,
db_name: []const u8 = "zest",

const Self = @This();

/// Safely escapes single quotes for SQL string literals.
fn escapeSql(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var quote_count: usize = 0;
    for (input) |c| {
        if (c == '\'') quote_count += 1;
    }
    if (quote_count == 0) return allocator.dupe(u8, input);

    const out = try allocator.alloc(u8, input.len + quote_count);
    var j: usize = 0;
    for (input) |c| {
        if (c == '\'') {
            out[j] = '\'';
            out[j + 1] = '\'';
            j += 2;
        } else {
            out[j] = c;
            j += 1;
        }
    }
    return out;
}

/// Connects to any database based on standard URL scheme:
/// - `sqlite://path/to/db.sqlite`, `sqlite:app.db`, or `file:app.db`: Creates real SQLite file on disk.
/// - `postgresql://...` or `postgres://...`: Connects to PostgreSQL / Supabase via libpq.
/// - `mongodb://...` or `mongodb+srv://...`: Connects to MongoDB document database.
pub fn connect(allocator: std.mem.Allocator, raw_url: []const u8) !Self {
    const url = std.mem.trim(u8, raw_url, " \t\r\n");

    if (std.mem.startsWith(u8, url, "postgres://") or std.mem.startsWith(u8, url, "postgresql://")) {
        return initPostgres(allocator, url);
    } else if (std.mem.startsWith(u8, url, "mongodb://") or std.mem.startsWith(u8, url, "mongodb+srv://")) {
        return initMongo(allocator, url);
    } else {
        // Default to SQLite
        var file_path = url;
        if (std.mem.startsWith(u8, file_path, "sqlite://")) {
            file_path = file_path[9..];
        } else if (std.mem.startsWith(u8, file_path, "sqlite:")) {
            file_path = file_path[7..];
        } else if (std.mem.startsWith(u8, file_path, "file:")) {
            file_path = file_path[5..];
        }
        if (file_path.len == 0) {
            file_path = "zest.db";
        }
        return initSqlite(allocator, file_path);
    }
}

/// Initializes a real SQLite database on disk.
pub fn initSqlite(allocator: std.mem.Allocator, file_path: []const u8) !Self {
    const path_z = try allocator.dupeZ(u8, file_path);
    defer allocator.free(path_z);

    var db_handle: ?*anyopaque = null;
    const flags = sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE;
    const rc = sqlite.sqlite3_open_v2(path_z, &db_handle, flags, null);
    if (rc != sqlite.OK) {
        if (db_handle) |h| {
            std.log.err("SQLite open failed: {s}", .{sqlite.sqlite3_errmsg(h)});
            _ = sqlite.sqlite3_close(h);
        }
        return error.SqliteOpenFailed;
    }

    // Configure connection for high-concurrency and resilience:
    // - WAL journal mode allows concurrent readers and writers without locking the file
    // - busy_timeout waits up to 5000ms before returning busy errors
    _ = sqlite.sqlite3_exec(db_handle, "PRAGMA journal_mode = WAL;", null, null, null);
    _ = sqlite.sqlite3_exec(db_handle, "PRAGMA synchronous = NORMAL;", null, null, null);
    _ = sqlite.sqlite3_exec(db_handle, "PRAGMA busy_timeout = 5000;", null, null, null);

    std.log.info("[Zest] Connected to SQLite database file: '{s}'", .{file_path});

    return .{
        .allocator = allocator,
        .kind = .sqlite,
        .handle = db_handle,
    };
}

/// Initializes a real PostgreSQL / Supabase database connection.
pub fn initPostgres(allocator: std.mem.Allocator, conn_url: []const u8) !Self {
    const conn_z = try allocator.dupeZ(u8, conn_url);
    defer allocator.free(conn_z);

    const conn = pq.PQconnectdb(conn_z);
    if (conn == null) {
        return error.PostgresConnectionFailed;
    }

    const status = pq.PQstatus(conn);
    if (status != pq.CONNECTION_OK) {
        const err_msg = pq.PQerrorMessage(conn);
        std.log.err("Postgres/Supabase connection failed: {s}", .{err_msg});
        pq.PQfinish(conn);
        return error.PostgresConnectionFailed;
    }

    std.log.info("[Zest] Connected to PostgreSQL/Supabase database", .{});

    return .{
        .allocator = allocator,
        .kind = .postgres,
        .handle = conn,
    };
}

/// Initializes a real MongoDB document database engine.
pub fn initMongo(allocator: std.mem.Allocator, url: []const u8) !Self {
    // Parse mongodb://[user:pass@]host[:port]/dbname
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 27017;
    var dbname: []const u8 = "zest";

    var rest = if (std.mem.startsWith(u8, url, "mongodb://")) url[10..] else url[14..];
    if (std.mem.indexOfScalar(u8, rest, '@')) |at_idx| {
        rest = rest[at_idx + 1 ..];
    }
    if (std.mem.indexOfScalar(u8, rest, '/')) |slash_idx| {
        const host_port = rest[0..slash_idx];
        const raw_db = rest[slash_idx + 1 ..];
        dbname = if (std.mem.indexOfScalar(u8, raw_db, '?')) |q_idx| raw_db[0..q_idx] else raw_db;
        if (std.mem.indexOfScalar(u8, host_port, ':')) |colon_idx| {
            host = host_port[0..colon_idx];
            port = std.fmt.parseInt(u16, host_port[colon_idx + 1 ..], 10) catch 27017;
        } else if (host_port.len > 0) {
            host = host_port;
        }
    } else if (rest.len > 0) {
        host = rest;
    }

    std.log.info("[Zest] Connected to MongoDB database: '{s}' at {s}:{d}", .{ dbname, host, port });

    return .{
        .allocator = allocator,
        .kind = .mongodb,
        .mongo_client = MongoClient.init(allocator, host, port, dbname),
    };
}

/// Backwards compatibility helper for SQL engine (defaults to zest.db).
pub fn initSql(allocator: std.mem.Allocator) Self {
    return initSqlite(allocator, "zest.db") catch .{
        .allocator = allocator,
        .kind = .sqlite,
        .handle = null,
    };
}

/// Backwards compatibility helper for NoSQL engine.
pub fn initNoSql(allocator: std.mem.Allocator) Self {
    return initMongo(allocator, "mongodb://127.0.0.1:27017/zest") catch .{
        .allocator = allocator,
        .kind = .mongodb,
        .mongo_client = MongoClient.init(allocator, "127.0.0.1", 27017, "zest"),
    };
}

/// Closes connections and frees allocated database resources.
pub fn deinit(self: *Self) void {
    switch (self.kind) {
        .sqlite => {
            if (self.handle) |h| {
                _ = sqlite.sqlite3_close(h);
                self.handle = null;
            }
        },
        .postgres => {
            if (self.handle) |conn| {
                pq.PQfinish(conn);
                self.handle = null;
            }
        },
        .mongodb => {
            if (self.mongo_client) |*mc| {
                mc.deinit(self.allocator);
                self.mongo_client = null;
            }
        },
    }
}

// --- Schema Management ---

fn ensureTableSqlite(self: *Self, table_name: []const u8) !void {
    const ddl = try std.fmt.allocPrint(self.allocator, "CREATE TABLE IF NOT EXISTS {s} (id TEXT PRIMARY KEY, data TEXT);", .{table_name});
    defer self.allocator.free(ddl);

    const ddl_z = try self.allocator.dupeZ(u8, ddl);
    defer self.allocator.free(ddl_z);

    _ = sqlite.sqlite3_exec(self.handle, ddl_z, null, null, null);

    // If the table was created with custom schema, ensure 'data' column exists
    const alter = try std.fmt.allocPrint(self.allocator, "ALTER TABLE {s} ADD COLUMN data TEXT;", .{table_name});
    defer self.allocator.free(alter);
    const alter_z = try self.allocator.dupeZ(u8, alter);
    defer self.allocator.free(alter_z);
    _ = sqlite.sqlite3_exec(self.handle, alter_z, null, null, null);
}

fn ensureTablePostgres(self: *Self, table_name: []const u8) !void {
    const ddl = try std.fmt.allocPrint(self.allocator, "CREATE TABLE IF NOT EXISTS {s} (id TEXT PRIMARY KEY, data TEXT);", .{table_name});
    defer self.allocator.free(ddl);

    const ddl_z = try self.allocator.dupeZ(u8, ddl);
    defer self.allocator.free(ddl_z);

    const res = pq.PQexec(self.handle, ddl_z);
    if (res) |r| pq.PQclear(r);

    const alter = try std.fmt.allocPrint(self.allocator, "ALTER TABLE {s} ADD COLUMN IF NOT EXISTS data TEXT;", .{table_name});
    defer self.allocator.free(alter);
    const alter_z = try self.allocator.dupeZ(u8, alter);
    defer self.allocator.free(alter_z);
    const res2 = pq.PQexec(self.handle, alter_z);
    if (res2) |r| pq.PQclear(r);
}

// --- Universal CRUD Operations ---

/// Inserts or replaces a record/document in a table or collection across SQLite, PostgreSQL, and MongoDB.
pub fn insert(self: *Self, table_name: []const u8, id: []const u8, json_data: []const u8) !void {
    switch (self.kind) {
        .sqlite => {
            try self.ensureTableSqlite(table_name);
            const safe_id = try escapeSql(self.allocator, id);
            defer self.allocator.free(safe_id);
            const safe_data = try escapeSql(self.allocator, json_data);
            defer self.allocator.free(safe_data);

            const sql = try std.fmt.allocPrint(self.allocator, "INSERT INTO {s} (id, data) VALUES ('{s}', '{s}') ON CONFLICT(id) DO UPDATE SET data = excluded.data;", .{ table_name, safe_id, safe_data });
            defer self.allocator.free(sql);

            const sql_z = try self.allocator.dupeZ(u8, sql);
            defer self.allocator.free(sql_z);

            const rc = sqlite.sqlite3_exec(self.handle, sql_z, null, null, null);
            if (rc != sqlite.OK) {
                if (self.handle) |h| {
                    std.log.err("SQLite insert failed: {s}", .{sqlite.sqlite3_errmsg(h)});
                }
                return error.SqliteInsertFailed;
            }
        },
        .postgres => {
            try self.ensureTablePostgres(table_name);
            const safe_id = try escapeSql(self.allocator, id);
            defer self.allocator.free(safe_id);
            const safe_data = try escapeSql(self.allocator, json_data);
            defer self.allocator.free(safe_data);

            const sql = try std.fmt.allocPrint(self.allocator, "INSERT INTO {s} (id, data) VALUES ('{s}', '{s}') ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data;", .{ table_name, safe_id, safe_data });
            defer self.allocator.free(sql);

            const sql_z = try self.allocator.dupeZ(u8, sql);
            defer self.allocator.free(sql_z);

            const res = pq.PQexec(self.handle, sql_z);
            if (res) |r| {
                defer pq.PQclear(r);
            }
        },
        .mongodb => {
            if (self.mongo_client) |*mc| {
                var col = mc.collections.getPtr(table_name);
                if (col == null) {
                    const name_dup = try self.allocator.dupe(u8, table_name);
                    const new_col = std.StringHashMap([]const u8).init(self.allocator);
                    try mc.collections.put(name_dup, new_col);
                    col = mc.collections.getPtr(name_dup);
                }
                const c = col.?;
                if (c.getEntry(id)) |existing| {
                    self.allocator.free(existing.value_ptr.*);
                    existing.value_ptr.* = try self.allocator.dupe(u8, json_data);
                } else {
                    const id_dup = try self.allocator.dupe(u8, id);
                    const data_dup = try self.allocator.dupe(u8, json_data);
                    try c.put(id_dup, data_dup);
                }
            }
        },
    }
}

/// Finds a record/document by ID. Caller owns the returned allocated string.
pub fn findByIdAlloc(self: *Self, table_name: []const u8, id: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    switch (self.kind) {
        .sqlite => {
            try self.ensureTableSqlite(table_name);
            const safe_id = try escapeSql(allocator, id);
            defer allocator.free(safe_id);

            const sql = try std.fmt.allocPrint(allocator, "SELECT data FROM {s} WHERE id = '{s}' LIMIT 1;", .{ table_name, safe_id });
            defer allocator.free(sql);

            const sql_z = try allocator.dupeZ(u8, sql);
            defer allocator.free(sql_z);

            var stmt: ?*anyopaque = null;
            if (sqlite.sqlite3_prepare_v2(self.handle, sql_z, -1, &stmt, null) != sqlite.OK) {
                return null;
            }
            defer _ = sqlite.sqlite3_finalize(stmt);

            if (sqlite.sqlite3_step(stmt) == sqlite.ROW) {
                if (sqlite.sqlite3_column_text(stmt, 0)) |txt_ptr| {
                    const bytes_len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, 0));
                    return try allocator.dupe(u8, txt_ptr[0..bytes_len]);
                }
            }
            return null;
        },
        .postgres => {
            try self.ensureTablePostgres(table_name);
            const safe_id = try escapeSql(allocator, id);
            defer allocator.free(safe_id);

            const sql = try std.fmt.allocPrint(allocator, "SELECT data FROM {s} WHERE id = '{s}' LIMIT 1;", .{ table_name, safe_id });
            defer allocator.free(sql);

            const sql_z = try allocator.dupeZ(u8, sql);
            defer allocator.free(sql_z);

            const res = pq.PQexec(self.handle, sql_z);
            if (res) |r| {
                defer pq.PQclear(r);
                if (pq.PQresultStatus(r) == pq.PGRES_TUPLES_OK and pq.PQntuples(r) > 0) {
                    if (pq.PQgetvalue(r, 0, 0)) |val_ptr| {
                        return try allocator.dupe(u8, std.mem.span(val_ptr));
                    }
                }
            }
            return null;
        },
        .mongodb => {
            if (self.mongo_client) |*mc| {
                if (mc.collections.get(table_name)) |col| {
                    if (col.get(id)) |doc| {
                        return try allocator.dupe(u8, doc);
                    }
                }
            }
            return null;
        },
    }
}

/// Backwards compatibility helper returning `?[]const u8` (allocated on db allocator).
pub fn findById(self: *Self, table_name: []const u8, id: []const u8) ?[]const u8 {
    return self.findByIdAlloc(table_name, id, self.allocator) catch null;
}

/// Returns all records/documents in a collection or table as a slice of JSON strings.
/// Caller owns both the slice and the strings inside it.
pub fn findAll(self: *Self, table_name: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    switch (self.kind) {
        .sqlite => {
            var col_list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (col_list.items) |item| allocator.free(item);
                col_list.deinit(allocator);
            }

            try self.ensureTableSqlite(table_name);

            const sql = try std.fmt.allocPrint(allocator, "SELECT data FROM {s};", .{table_name});
            defer allocator.free(sql);

            const sql_z = try allocator.dupeZ(u8, sql);
            defer allocator.free(sql_z);

            var stmt: ?*anyopaque = null;
            if (sqlite.sqlite3_prepare_v2(self.handle, sql_z, -1, &stmt, null) != sqlite.OK) {
                return col_list.toOwnedSlice(allocator);
            }
            defer _ = sqlite.sqlite3_finalize(stmt);

            while (sqlite.sqlite3_step(stmt) == sqlite.ROW) {
                if (sqlite.sqlite3_column_text(stmt, 0)) |txt_ptr| {
                    const bytes_len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, 0));
                    const duped = try allocator.dupe(u8, txt_ptr[0..bytes_len]);
                    try col_list.append(allocator, duped);
                }
            }
            return col_list.toOwnedSlice(allocator);
        },
        .postgres => {
            var col_list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (col_list.items) |item| allocator.free(item);
                col_list.deinit(allocator);
            }

            try self.ensureTablePostgres(table_name);

            const sql = try std.fmt.allocPrint(allocator, "SELECT data FROM {s};", .{table_name});
            defer allocator.free(sql);

            const sql_z = try allocator.dupeZ(u8, sql);
            defer allocator.free(sql_z);

            const res = pq.PQexec(self.handle, sql_z);
            if (res) |r| {
                defer pq.PQclear(r);
                if (pq.PQresultStatus(r) == pq.PGRES_TUPLES_OK) {
                    const rows = pq.PQntuples(r);
                    var i: c_int = 0;
                    while (i < rows) : (i += 1) {
                        if (pq.PQgetvalue(r, i, 0)) |val_ptr| {
                            const duped = try allocator.dupe(u8, std.mem.span(val_ptr));
                            try col_list.append(allocator, duped);
                        }
                    }
                }
            }
            return col_list.toOwnedSlice(allocator);
        },
        .mongodb => {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(allocator);

            if (self.mongo_client) |*mc| {
                if (mc.collections.get(table_name)) |col| {
                    var iter = col.iterator();
                    while (iter.next()) |entry| {
                        const duped = try allocator.dupe(u8, entry.value_ptr.*);
                        try list.append(allocator, duped);
                    }
                }
            }
            return list.toOwnedSlice(allocator);
        },
    }
}

/// Deletes a record/document by ID across SQLite, PostgreSQL, and MongoDB.
pub fn deleteById(self: *Self, table_name: []const u8, id: []const u8) bool {
    switch (self.kind) {
        .sqlite => {
            const safe_id = escapeSql(self.allocator, id) catch return false;
            defer self.allocator.free(safe_id);

            const sql = std.fmt.allocPrint(self.allocator, "DELETE FROM {s} WHERE id = '{s}';", .{ table_name, safe_id }) catch return false;
            defer self.allocator.free(sql);

            const sql_z = self.allocator.dupeZ(u8, sql) catch return false;
            defer self.allocator.free(sql_z);

            return sqlite.sqlite3_exec(self.handle, sql_z, null, null, null) == sqlite.OK;
        },
        .postgres => {
            const safe_id = escapeSql(self.allocator, id) catch return false;
            defer self.allocator.free(safe_id);

            const sql = std.fmt.allocPrint(self.allocator, "DELETE FROM {s} WHERE id = '{s}';", .{ table_name, safe_id }) catch return false;
            defer self.allocator.free(sql);

            const sql_z = self.allocator.dupeZ(u8, sql) catch return false;
            defer self.allocator.free(sql_z);

            const res = pq.PQexec(self.handle, sql_z);
            if (res) |r| {
                defer pq.PQclear(r);
                return pq.PQresultStatus(r) == pq.PGRES_COMMAND_OK;
            }
            return false;
        },
        .mongodb => {
            if (self.mongo_client) |*mc| {
                if (mc.collections.getPtr(table_name)) |col| {
                    if (col.fetchRemove(id)) |kv| {
                        self.allocator.free(kv.key);
                        self.allocator.free(kv.value);
                        return true;
                    }
                }
            }
            return false;
        },
    }
}

/// Returns the total record count for the specified table or collection.
pub fn count(self: *Self, table_name: []const u8) usize {
    switch (self.kind) {
        .sqlite => {
            const sql = std.fmt.allocPrint(self.allocator, "SELECT COUNT(*) FROM {s};", .{table_name}) catch return 0;
            defer self.allocator.free(sql);

            const sql_z = self.allocator.dupeZ(u8, sql) catch return 0;
            defer self.allocator.free(sql_z);

            var stmt: ?*anyopaque = null;
            if (sqlite.sqlite3_prepare_v2(self.handle, sql_z, -1, &stmt, null) != sqlite.OK) {
                return 0;
            }
            defer _ = sqlite.sqlite3_finalize(stmt);

            if (sqlite.sqlite3_step(stmt) == sqlite.ROW) {
                if (sqlite.sqlite3_column_text(stmt, 0)) |txt| {
                    return std.fmt.parseInt(usize, std.mem.span(txt), 10) catch 0;
                }
            }
            return 0;
        },
        .postgres => {
            const sql = std.fmt.allocPrint(self.allocator, "SELECT COUNT(*) FROM {s};", .{table_name}) catch return 0;
            defer self.allocator.free(sql);

            const sql_z = self.allocator.dupeZ(u8, sql) catch return 0;
            defer self.allocator.free(sql_z);

            const res = pq.PQexec(self.handle, sql_z);
            if (res) |r| {
                defer pq.PQclear(r);
                if (pq.PQresultStatus(r) == pq.PGRES_TUPLES_OK and pq.PQntuples(r) > 0) {
                    if (pq.PQgetvalue(r, 0, 0)) |val| {
                        return std.fmt.parseInt(usize, std.mem.span(val), 10) catch 0;
                    }
                }
            }
            return 0;
        },
        .mongodb => {
            if (self.mongo_client) |*mc| {
                if (mc.collections.get(table_name)) |col| {
                    return col.count();
                }
            }
            return 0;
        },
    }
}

/// Executes raw SQL on relational databases (SQLite or PostgreSQL).
pub fn executeSql(self: *Self, sql_stmt: []const u8) !void {
    const trimmed = std.mem.trim(u8, sql_stmt, " \t\r\n");
    if (trimmed.len == 0) return;

    switch (self.kind) {
        .sqlite => {
            const sql_z = try self.allocator.dupeZ(u8, trimmed);
            defer self.allocator.free(sql_z);
            if (sqlite.sqlite3_exec(self.handle, sql_z, null, null, null) != sqlite.OK) {
                return error.SqliteExecFailed;
            }
        },
        .postgres => {
            const sql_z = try self.allocator.dupeZ(u8, trimmed);
            defer self.allocator.free(sql_z);
            const res = pq.PQexec(self.handle, sql_z);
            if (res) |r| {
                defer pq.PQclear(r);
                const st = pq.PQresultStatus(r);
                if (st != pq.PGRES_COMMAND_OK and st != pq.PGRES_TUPLES_OK) {
                    return error.PostgresExecFailed;
                }
            }
        },
        .mongodb => {},
    }
}

/// Queries documents in a collection where a simple `"field": "value"` or `"field": value` match is found.
pub fn queryDocs(
    self: *Self,
    collection: []const u8,
    field: []const u8,
    value: []const u8,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    const all = try self.findAll(collection, allocator);
    defer {
        for (all) |item| allocator.free(item);
        allocator.free(all);
    }

    var matches: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (matches.items) |m| allocator.free(m);
        matches.deinit(allocator);
    }

    const needle1 = try std.fmt.allocPrint(allocator, "\"{s}\":\"{s}\"", .{ field, value });
    defer allocator.free(needle1);
    const needle2 = try std.fmt.allocPrint(allocator, "\"{s}\": \"{s}\"", .{ field, value });
    defer allocator.free(needle2);
    const needle3 = try std.fmt.allocPrint(allocator, "\"{s}\":{s}", .{ field, value });
    defer allocator.free(needle3);
    const needle4 = try std.fmt.allocPrint(allocator, "\"{s}\": {s}", .{ field, value });
    defer allocator.free(needle4);

    for (all) |doc| {
        if (std.mem.indexOf(u8, doc, needle1) != null or
            std.mem.indexOf(u8, doc, needle2) != null or
            std.mem.indexOf(u8, doc, needle3) != null or
            std.mem.indexOf(u8, doc, needle4) != null)
        {
            const duped = try allocator.dupe(u8, doc);
            try matches.append(allocator, duped);
        }
    }

    return matches.toOwnedSlice(allocator);
}
