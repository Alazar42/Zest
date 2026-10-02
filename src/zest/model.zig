const std = @import("std");
const Db = @import("db.zig");
const QueryBuilder = @import("query.zig").QueryBuilder;
const uuid = @import("uuid.zig");

/// Comptime Model interface that any struct can extend using:
/// `pub const model = zest.Model(@This());`
///
/// Provides schema reflection, relational SQL persistence (PostgreSQL & SQLite)
/// with real typed columns, document persistence (MongoDB), and high-level ORM operations.
pub fn Model(comptime Self: type) type {
    return struct {
        /// Serializes a model instance into a JSON string using the provided allocator.
        pub fn toJson(instance: *const Self, allocator: std.mem.Allocator) ![]u8 {
            return std.json.Stringify.valueAlloc(allocator, instance.*, .{});
        }

        /// Deserializes a model instance from JSON bytes.
        pub fn fromJson(allocator: std.mem.Allocator, json_bytes: []const u8) !std.json.Parsed(Self) {
            return std.json.parseFromSlice(Self, allocator, json_bytes, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            });
        }

        /// Returns the database table or collection name (defaults to the struct name, or custom `table_name`).
        pub fn tableName() []const u8 {
            if (@hasDecl(Self, "table_name")) {
                return Self.table_name;
            }
            const full_name = @typeName(Self);
            if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |dot| {
                return full_name[dot + 1 ..];
            }
            return full_name;
        }

        /// Returns the primary key column name (defaults to "id", or custom `primary_key`).
        pub fn primaryKey() []const u8 {
            if (@hasDecl(Self, "primary_key")) {
                return Self.primary_key;
            }
            return "id";
        }

        /// Returns a slice of all field names defined on this model.
        pub fn fieldNames() []const []const u8 {
            const fields_info = @typeInfo(Self).@"struct".fields;
            comptime var names: [fields_info.len][]const u8 = undefined;
            inline for (fields_info, 0..) |f, i| {
                names[i] = f.name;
            }
            const res = names;
            return &res;
        }

        /// Returns the number of fields in the model.
        pub fn fieldCount() usize {
            return @typeInfo(Self).@"struct".fields.len;
        }

        /// Returns the corresponding SQL column type for a given Zig field type.
        pub fn sqlColumnType(comptime T: type) []const u8 {
            const ActualType = switch (@typeInfo(T)) {
                .optional => |opt| opt.child,
                else => T,
            };
            return switch (@typeInfo(ActualType)) {
                .int => |info| if (info.bits > 32) "BIGINT" else "INTEGER",
                .float => "REAL",
                .bool => "BOOLEAN",
                else => "TEXT",
            };
        }

        /// Generates SQL DDL to create the corresponding relational table schema with real columns.
        pub fn createTableSql(allocator: std.mem.Allocator) ![]u8 {
            var ddl_query: std.ArrayList(u8) = .empty;
            errdefer ddl_query.deinit(allocator);

            const prefix = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s} (", .{tableName()});
            defer allocator.free(prefix);
            try ddl_query.appendSlice(allocator, prefix);

            const fields_info = @typeInfo(Self).@"struct".fields;
            const pk = primaryKey();

            inline for (fields_info, 0..) |f, i| {
                const type_str = sqlColumnType(f.type);
                const is_pk = std.mem.eql(u8, f.name, pk);
                const col_def = if (is_pk)
                    try std.fmt.allocPrint(allocator, "{s} {s} PRIMARY KEY", .{ f.name, type_str })
                else
                    try std.fmt.allocPrint(allocator, "{s} {s}", .{ f.name, type_str });
                defer allocator.free(col_def);
                try ddl_query.appendSlice(allocator, col_def);

                if (i + 1 < fields_info.len) {
                    try ddl_query.appendSlice(allocator, ", ");
                }
            }
            try ddl_query.appendSlice(allocator, ");");
            return ddl_query.toOwnedSlice(allocator);
        }

        // --- ORM Database Methods (Dual SQL / NoSQL) ---

        /// Formats any ID type into a string slice.
        pub fn idToString(buf: *[64]u8, id: anytype) []const u8 {
            const T = @TypeOf(id);
            if (T == []const u8 or T == []u8) {
                return id;
            }
            if (@typeInfo(T) == .pointer) {
                const ptr_info = @typeInfo(T).pointer;
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    return id;
                }
                if (ptr_info.size == .one and @typeInfo(ptr_info.child) == .array and @typeInfo(ptr_info.child).array.child == u8) {
                    return id[0..];
                }
            }
            if (@typeInfo(T) == .optional) {
                if (id) |val| {
                    return idToString(buf, val);
                } else {
                    return "0";
                }
            }
            return std.fmt.bufPrint(buf, "{any}", .{id}) catch "0";
        }

        /// Extracts the primary key value from an instance into a string.
        pub fn extractId(buf: *[64]u8, instance: *const Self) []const u8 {
            const pk = primaryKey();
            inline for (@typeInfo(Self).@"struct".fields) |f| {
                if (std.mem.eql(u8, f.name, pk)) {
                    const val = @field(instance, f.name);
                    return idToString(buf, val);
                }
            }
            return "0";
        }

        /// Formats a Zig value as a valid SQL literal.
        fn appendSqlValue(
            sql_buf: *std.ArrayList(u8),
            allocator: std.mem.Allocator,
            val: anytype,
        ) !void {
            const T = @TypeOf(val);
            switch (@typeInfo(T)) {
                .optional => {
                    if (val) |v| {
                        try appendSqlValue(sql_buf, allocator, v);
                    } else {
                        try sql_buf.appendSlice(allocator, "NULL");
                    }
                },
                .bool => {
                    try sql_buf.appendSlice(allocator, if (val) "TRUE" else "FALSE");
                },
                .int => {
                    const s = try std.fmt.allocPrint(allocator, "{d}", .{val});
                    defer allocator.free(s);
                    try sql_buf.appendSlice(allocator, s);
                },
                .float => {
                    const s = try std.fmt.allocPrint(allocator, "{d}", .{val});
                    defer allocator.free(s);
                    try sql_buf.appendSlice(allocator, s);
                },
                .pointer => |ptr_info| {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        const escaped = try Db.escapeSql(allocator, val);
                        defer allocator.free(escaped);
                        try sql_buf.append(allocator, '\'');
                        try sql_buf.appendSlice(allocator, escaped);
                        try sql_buf.append(allocator, '\'');
                    } else if (ptr_info.size == .one and @typeInfo(ptr_info.child) == .array and @typeInfo(ptr_info.child).array.child == u8) {
                        const slice: []const u8 = val[0..];
                        const escaped = try Db.escapeSql(allocator, slice);
                        defer allocator.free(escaped);
                        try sql_buf.append(allocator, '\'');
                        try sql_buf.appendSlice(allocator, escaped);
                        try sql_buf.append(allocator, '\'');
                    } else {
                        const json = try std.json.Stringify.valueAlloc(allocator, val, .{});
                        defer allocator.free(json);
                        const escaped = try Db.escapeSql(allocator, json);
                        defer allocator.free(escaped);
                        try sql_buf.append(allocator, '\'');
                        try sql_buf.appendSlice(allocator, escaped);
                        try sql_buf.append(allocator, '\'');
                    }
                },
                .@"enum" => {
                    const tag = @tagName(val);
                    const escaped = try Db.escapeSql(allocator, tag);
                    defer allocator.free(escaped);
                    try sql_buf.append(allocator, '\'');
                    try sql_buf.appendSlice(allocator, escaped);
                    try sql_buf.append(allocator, '\'');
                },
                else => {
                    const json = try std.json.Stringify.valueAlloc(allocator, val, .{});
                    defer allocator.free(json);
                    const escaped = try Db.escapeSql(allocator, json);
                    defer allocator.free(escaped);
                    try sql_buf.append(allocator, '\'');
                    try sql_buf.appendSlice(allocator, escaped);
                    try sql_buf.append(allocator, '\'');
                },
            }
        }

        /// Automatically synchronizes the table schema with real typed columns in the database.
        pub fn sync(db: *Db) !void {
            if (db.kind == .mongodb) return;

            // 1. Create table if not exists with all fields
            const ddl = try createTableSql(db.allocator);
            defer db.allocator.free(ddl);
            db.executeSql(ddl) catch {};

            // 2. Ensure each column exists (schema synchronization)
            const table = tableName();
            const fields_info = @typeInfo(Self).@"struct".fields;
            inline for (fields_info) |f| {
                const type_str = sqlColumnType(f.type);
                if (db.kind == .postgres) {
                    const alter = try std.fmt.allocPrint(db.allocator, "ALTER TABLE {s} ADD COLUMN IF NOT EXISTS \"{s}\" {s};", .{ table, f.name, type_str });
                    defer db.allocator.free(alter);
                    db.executeSql(alter) catch {};
                } else if (db.kind == .sqlite) {
                    const alter = try std.fmt.allocPrint(db.allocator, "ALTER TABLE {s} ADD COLUMN \"{s}\" {s};", .{ table, f.name, type_str });
                    defer db.allocator.free(alter);
                    _ = db.executeSql(alter) catch {};
                }
            }
        }

        /// Saves (inserts or updates) a model instance in the database using real relational columns.
        pub fn save(db: *Db, allocator: std.mem.Allocator, instance: *const Self) !void {
            var inst = instance.*;
            var uuid_buf: [36]u8 = undefined;
            const pk = primaryKey();

            inline for (@typeInfo(Self).@"struct".fields) |f| {
                if (std.mem.eql(u8, f.name, pk)) {
                    if (@typeInfo(f.type) == .optional) {
                        const opt_child = @typeInfo(f.type).optional.child;
                        if (opt_child == []const u8 or opt_child == []u8) {
                            if (@field(inst, f.name) == null or @field(inst, f.name).?.len == 0) {
                                @field(inst, f.name) = uuid.v4(&uuid_buf);
                            }
                        }
                    }
                }
            }

            var id_buf: [64]u8 = undefined;
            const id_str = extractId(&id_buf, &inst);

            if (db.kind == .mongodb) {
                const json_str = try toJson(&inst, allocator);
                defer allocator.free(json_str);
                try db.insert(tableName(), id_str, json_str);
                return;
            }

            // Relational SQL (SQLite / PostgreSQL)
            try sync(db);

            const table = tableName();
            const fields_info = @typeInfo(Self).@"struct".fields;

            var sql_buf: std.ArrayList(u8) = .empty;
            defer sql_buf.deinit(allocator);

            try sql_buf.appendSlice(allocator, "INSERT INTO ");
            try sql_buf.appendSlice(allocator, table);
            try sql_buf.appendSlice(allocator, " (");

            inline for (fields_info, 0..) |f, i| {
                if (i > 0) try sql_buf.appendSlice(allocator, ", ");
                try sql_buf.append(allocator, '"');
                try sql_buf.appendSlice(allocator, f.name);
                try sql_buf.append(allocator, '"');
            }

            try sql_buf.appendSlice(allocator, ") VALUES (");

            inline for (fields_info, 0..) |f, i| {
                if (i > 0) try sql_buf.appendSlice(allocator, ", ");
                const val = @field(inst, f.name);
                try appendSqlValue(&sql_buf, allocator, val);
            }

            try sql_buf.appendSlice(allocator, ") ON CONFLICT (\"");
            try sql_buf.appendSlice(allocator, pk);
            try sql_buf.appendSlice(allocator, "\") DO ");

            var non_pk_count: usize = 0;
            inline for (fields_info) |f| {
                if (!std.mem.eql(u8, f.name, pk)) non_pk_count += 1;
            }

            if (non_pk_count == 0) {
                try sql_buf.appendSlice(allocator, "NOTHING;");
            } else {
                try sql_buf.appendSlice(allocator, "UPDATE SET ");
                var updated: usize = 0;
                inline for (fields_info) |f| {
                    if (!std.mem.eql(u8, f.name, pk)) {
                        if (updated > 0) try sql_buf.appendSlice(allocator, ", ");
                        if (db.kind == .postgres) {
                            const s = try std.fmt.allocPrint(allocator, "\"{s}\" = EXCLUDED.\"{s}\"", .{ f.name, f.name });
                            defer allocator.free(s);
                            try sql_buf.appendSlice(allocator, s);
                        } else {
                            const s = try std.fmt.allocPrint(allocator, "\"{s}\" = excluded.\"{s}\"", .{ f.name, f.name });
                            defer allocator.free(s);
                            try sql_buf.appendSlice(allocator, s);
                        }
                        updated += 1;
                    }
                }
                try sql_buf.appendSlice(allocator, ";");
            }

            try db.executeSql(sql_buf.items);
        }

        /// Converts an active SQLite row into a JSON object string according to model field types.
        pub fn sqliteRowToJson(allocator: std.mem.Allocator, stmt: ?*anyopaque) ![]u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);

            try out.append(allocator, '{');
            const cols = Db.sqlite.sqlite3_column_count(stmt);
            var i: c_int = 0;
            while (i < cols) : (i += 1) {
                if (i > 0) try out.append(allocator, ',');

                const name_c = Db.sqlite.sqlite3_column_name(stmt, i);
                const name = if (name_c) |nc| std.mem.span(nc) else "";

                try out.append(allocator, '"');
                try out.appendSlice(allocator, name);
                try out.appendSlice(allocator, "\":");

                var is_bool = false;
                inline for (@typeInfo(Self).@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, name)) {
                        const child = switch (@typeInfo(f.type)) {
                            .optional => |opt| opt.child,
                            else => f.type,
                        };
                        if (child == bool) is_bool = true;
                    }
                }

                const col_type = Db.sqlite.sqlite3_column_type(stmt, i);
                switch (col_type) {
                    Db.sqlite.NULL => try out.appendSlice(allocator, "null"),
                    Db.sqlite.INTEGER => {
                        const val = Db.sqlite.sqlite3_column_int64(stmt, i);
                        if (is_bool) {
                            try out.appendSlice(allocator, if (val != 0) "true" else "false");
                        } else {
                            const s = try std.fmt.allocPrint(allocator, "{d}", .{val});
                            defer allocator.free(s);
                            try out.appendSlice(allocator, s);
                        }
                    },
                    Db.sqlite.FLOAT => {
                        const val = Db.sqlite.sqlite3_column_double(stmt, i);
                        const s = try std.fmt.allocPrint(allocator, "{d}", .{val});
                        defer allocator.free(s);
                        try out.appendSlice(allocator, s);
                    },
                    else => {
                        if (Db.sqlite.sqlite3_column_text(stmt, i)) |txt| {
                            const len: usize = @intCast(Db.sqlite.sqlite3_column_bytes(stmt, i));
                            const slice = txt[0..len];
                            if (is_bool) {
                                if (std.mem.eql(u8, slice, "1") or std.mem.eql(u8, slice, "true")) {
                                    try out.appendSlice(allocator, "true");
                                } else {
                                    try out.appendSlice(allocator, "false");
                                }
                            } else if ((std.mem.startsWith(u8, slice, "{") and std.mem.endsWith(u8, slice, "}")) or
                                       (std.mem.startsWith(u8, slice, "[") and std.mem.endsWith(u8, slice, "]")))
                            {
                                try out.appendSlice(allocator, slice);
                            } else {
                                try out.append(allocator, '"');
                                for (slice) |ch| {
                                    switch (ch) {
                                        '"' => try out.appendSlice(allocator, "\\\""),
                                        '\\' => try out.appendSlice(allocator, "\\\\"),
                                        '\n' => try out.appendSlice(allocator, "\\n"),
                                        '\r' => try out.appendSlice(allocator, "\\r"),
                                        '\t' => try out.appendSlice(allocator, "\\t"),
                                        else => try out.append(allocator, ch),
                                    }
                                }
                                try out.append(allocator, '"');
                            }
                        } else {
                            try out.appendSlice(allocator, "null");
                        }
                    },
                }
            }
            try out.append(allocator, '}');
            return out.toOwnedSlice(allocator);
        }

        /// Helper to parse a JSON row, with fallback for legacy records.
        pub fn parseRowJson(allocator: std.mem.Allocator, row_json: []const u8) !std.json.Parsed(Self) {
            return fromJson(allocator, row_json) catch |err| {
                const pattern = "\"data\":\"";
                if (std.mem.indexOf(u8, row_json, pattern)) |idx| {
                    const start = idx + pattern.len;
                    var end = start;
                    while (end < row_json.len) : (end += 1) {
                        if (row_json[end] == '"' and row_json[end - 1] != '\\') break;
                    }
                    if (end < row_json.len) {
                        const raw = row_json[start..end];
                        var unescaped: std.ArrayList(u8) = .empty;
                        defer unescaped.deinit(allocator);
                        var j: usize = 0;
                        while (j < raw.len) {
                            if (raw[j] == '\\' and j + 1 < raw.len and raw[j + 1] == '"') {
                                try unescaped.append(allocator, '"');
                                j += 2;
                            } else {
                                try unescaped.append(allocator, raw[j]);
                                j += 1;
                            }
                        }
                        return fromJson(allocator, unescaped.items) catch err;
                    }
                }
                return err;
            };
        }

        /// Finds a model instance by ID in the database using relational SQL.
        pub fn find(db: *Db, allocator: std.mem.Allocator, id: anytype) !?std.json.Parsed(Self) {
            var id_buf: [64]u8 = undefined;
            const id_str = idToString(&id_buf, id);

            if (db.kind == .mongodb) {
                const doc_opt = try db.findByIdAlloc(tableName(), id_str, allocator);
                const doc = doc_opt orelse return null;
                defer allocator.free(doc);
                return try fromJson(allocator, doc);
            }

            try sync(db);

            const table = tableName();
            const pk = primaryKey();
            const safe_id = try Db.escapeSql(allocator, id_str);
            defer allocator.free(safe_id);

            if (db.kind == .postgres) {
                const sql = try std.fmt.allocPrint(allocator, "SELECT row_to_json(t) FROM (SELECT * FROM {s} WHERE \"{s}\" = '{s}' LIMIT 1) t;", .{ table, pk, safe_id });
                defer allocator.free(sql);

                const sql_z = try allocator.dupeZ(u8, sql);
                defer allocator.free(sql_z);

                const res = Db.pq.PQexec(db.handle, sql_z);
                if (res) |r| {
                    defer Db.pq.PQclear(r);
                    if (Db.pq.PQresultStatus(r) == Db.pq.PGRES_TUPLES_OK and Db.pq.PQntuples(r) > 0) {
                        if (Db.pq.PQgetvalue(r, 0, 0)) |val_ptr| {
                            const row_json = std.mem.span(val_ptr);
                            return try parseRowJson(allocator, row_json);
                        }
                    }
                }
                return null;
            } else if (db.kind == .sqlite) {
                const sql = try std.fmt.allocPrint(allocator, "SELECT * FROM {s} WHERE \"{s}\" = '{s}' LIMIT 1;", .{ table, pk, safe_id });
                defer allocator.free(sql);

                const sql_z = try allocator.dupeZ(u8, sql);
                defer allocator.free(sql_z);

                var stmt: ?*anyopaque = null;
                if (Db.sqlite.sqlite3_prepare_v2(db.handle, sql_z, -1, &stmt, null) != Db.sqlite.OK) {
                    return null;
                }
                defer _ = Db.sqlite.sqlite3_finalize(stmt);

                if (Db.sqlite.sqlite3_step(stmt) == Db.sqlite.ROW) {
                    const row_json = try sqliteRowToJson(allocator, stmt);
                    defer allocator.free(row_json);
                    return try parseRowJson(allocator, row_json);
                }
                return null;
            }
            return null;
        }

        /// Retrieves all records for this model from the database.
        pub fn findAll(db: *Db, allocator: std.mem.Allocator) ![][]const u8 {
            if (db.kind == .mongodb) {
                return db.findAll(tableName(), allocator);
            }

            try sync(db);

            var list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (list.items) |item| allocator.free(item);
                list.deinit(allocator);
            }

            const table = tableName();
            if (db.kind == .postgres) {
                const sql = try std.fmt.allocPrint(allocator, "SELECT row_to_json(t) FROM (SELECT * FROM {s}) t;", .{table});
                defer allocator.free(sql);

                const sql_z = try allocator.dupeZ(u8, sql);
                defer allocator.free(sql_z);

                const res = Db.pq.PQexec(db.handle, sql_z);
                if (res) |r| {
                    defer Db.pq.PQclear(r);
                    if (Db.pq.PQresultStatus(r) == Db.pq.PGRES_TUPLES_OK) {
                        const rows = Db.pq.PQntuples(r);
                        var i: c_int = 0;
                        while (i < rows) : (i += 1) {
                            if (Db.pq.PQgetvalue(r, i, 0)) |val_ptr| {
                                const duped = try allocator.dupe(u8, std.mem.span(val_ptr));
                                try list.append(allocator, duped);
                            }
                        }
                    }
                }
                return list.toOwnedSlice(allocator);
            } else if (db.kind == .sqlite) {
                const sql = try std.fmt.allocPrint(allocator, "SELECT * FROM {s};", .{table});
                defer allocator.free(sql);

                const sql_z = try allocator.dupeZ(u8, sql);
                defer allocator.free(sql_z);

                var stmt: ?*anyopaque = null;
                if (Db.sqlite.sqlite3_prepare_v2(db.handle, sql_z, -1, &stmt, null) != Db.sqlite.OK) {
                    return list.toOwnedSlice(allocator);
                }
                defer _ = Db.sqlite.sqlite3_finalize(stmt);

                while (Db.sqlite.sqlite3_step(stmt) == Db.sqlite.ROW) {
                    const row_json = try sqliteRowToJson(allocator, stmt);
                    try list.append(allocator, row_json);
                }
                return list.toOwnedSlice(allocator);
            }
            return list.toOwnedSlice(allocator);
        }

        /// Deletes a model instance by ID from the database using SQL.
        pub fn delete(db: *Db, id: anytype) bool {
            var id_buf: [64]u8 = undefined;
            const id_str = idToString(&id_buf, id);

            if (db.kind == .mongodb) {
                return db.deleteById(tableName(), id_str);
            }

            const table = tableName();
            const pk = primaryKey();
            const safe_id = Db.escapeSql(db.allocator, id_str) catch return false;
            defer db.allocator.free(safe_id);

            const sql = std.fmt.allocPrint(db.allocator, "DELETE FROM {s} WHERE \"{s}\" = '{s}';", .{ table, pk, safe_id }) catch return false;
            defer db.allocator.free(sql);

            db.executeSql(sql) catch return false;
            return true;
        }

        /// Returns the total record count for this model's table or collection.
        pub fn count(db: *Db) usize {
            if (db.kind == .mongodb) {
                return db.count(tableName());
            }

            const table = tableName();
            if (db.kind == .postgres) {
                const sql = std.fmt.allocPrint(db.allocator, "SELECT COUNT(*) FROM {s};", .{table}) catch return 0;
                defer db.allocator.free(sql);
                const sql_z = db.allocator.dupeZ(u8, sql) catch return 0;
                defer db.allocator.free(sql_z);
                const res = Db.pq.PQexec(db.handle, sql_z);
                if (res) |r| {
                    defer Db.pq.PQclear(r);
                    if (Db.pq.PQresultStatus(r) == Db.pq.PGRES_TUPLES_OK and Db.pq.PQntuples(r) > 0) {
                        if (Db.pq.PQgetvalue(r, 0, 0)) |val| {
                            return std.fmt.parseInt(usize, std.mem.span(val), 10) catch 0;
                        }
                    }
                }
                return 0;
            } else if (db.kind == .sqlite) {
                const sql = std.fmt.allocPrint(db.allocator, "SELECT COUNT(*) FROM {s};", .{table}) catch return 0;
                defer db.allocator.free(sql);
                const sql_z = db.allocator.dupeZ(u8, sql) catch return 0;
                defer db.allocator.free(sql_z);
                var stmt: ?*anyopaque = null;
                if (Db.sqlite.sqlite3_prepare_v2(db.handle, sql_z, -1, &stmt, null) != Db.sqlite.OK) return 0;
                defer _ = Db.sqlite.sqlite3_finalize(stmt);
                if (Db.sqlite.sqlite3_step(stmt) == Db.sqlite.ROW) {
                    return @intCast(Db.sqlite.sqlite3_column_int64(stmt, 0));
                }
                return 0;
            }
            return 0;
        }

        /// Creates a fluent query builder to filter, sort, paginate, and query instances of this model.
        pub fn query(db: *Db, allocator: std.mem.Allocator) QueryBuilder(Self) {
            return QueryBuilder(Self).init(db, allocator);
        }

        /// Loads all associated records of type TargetModel where TargetModel.<foreign_key> == self.id.
        pub fn hasMany(
            instance: *const Self,
            comptime TargetModel: type,
            foreign_key: []const u8,
            db: *Db,
            allocator: std.mem.Allocator,
        ) ![]std.json.Parsed(TargetModel) {
            var id_buf: [64]u8 = undefined;
            const self_id = extractId(&id_buf, instance);

            var q = TargetModel.model.query(db, allocator);
            _ = q.where(foreign_key, .eq, self_id);
            return q.exec();
        }

        /// Loads the single parent record of type ParentModel where ParentModel.primary_key == self.<foreign_key>.
        pub fn belongsTo(
            instance: *const Self,
            comptime ParentModel: type,
            foreign_key: []const u8,
            db: *Db,
            allocator: std.mem.Allocator,
        ) !?std.json.Parsed(ParentModel) {
            var fk_buf: [64]u8 = undefined;
            var fk_str: ?[]const u8 = null;

            inline for (@typeInfo(Self).@"struct".fields) |f| {
                if (std.mem.eql(u8, f.name, foreign_key)) {
                    const val = @field(instance, f.name);
                    fk_str = idToString(&fk_buf, val);
                }
            }

            const parent_id = fk_str orelse return null;
            return ParentModel.model.find(db, allocator, parent_id);
        }
    };
}
