const std = @import("std");
const Db = @import("db.zig");
const QueryBuilder = @import("query.zig").QueryBuilder;

/// Comptime Model interface that any struct can extend using:
/// `pub const model = zest.Model(@This());`
///
/// Provides JSON serialization/deserialization, schema reflection, and high-level ORM
/// operations that work seamlessly across both SQL and NoSQL database engines.
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

        /// Generates SQL DDL to create the corresponding table schema.
        pub fn createTableSql(allocator: std.mem.Allocator) ![]u8 {
            var ddl_query: std.ArrayList(u8) = .empty;
            errdefer ddl_query.deinit(allocator);

            const prefix = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s} (", .{tableName()});
            defer allocator.free(prefix);
            try ddl_query.appendSlice(allocator, prefix);

            const fields_info = @typeInfo(Self).@"struct".fields;
            const pk = primaryKey();

            inline for (fields_info, 0..) |f, i| {
                const type_str = switch (@typeInfo(f.type)) {
                    .int => "INTEGER",
                    .float => "REAL",
                    .bool => "BOOLEAN",
                    else => "TEXT",
                };
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
        fn idToString(buf: *[64]u8, id: anytype) []const u8 {
            const T = @TypeOf(id);
            if (T == []const u8 or T == []u8) {
                return id;
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
        fn extractId(buf: *[64]u8, instance: *const Self) []const u8 {
            const pk = primaryKey();
            inline for (@typeInfo(Self).@"struct".fields) |f| {
                if (std.mem.eql(u8, f.name, pk)) {
                    const val = @field(instance, f.name);
                    return idToString(buf, val);
                }
            }
            return "0";
        }

        /// Saves (inserts or updates) a model instance in the database (SQL or NoSQL).
        pub fn save(db: *Db, allocator: std.mem.Allocator, instance: *const Self) !void {
            var id_buf: [64]u8 = undefined;
            const id_str = extractId(&id_buf, instance);

            const json_str = try toJson(instance, allocator);
            defer allocator.free(json_str);

            try db.insert(tableName(), id_str, json_str);
        }

        /// Finds a model instance by ID in the database (SQL or NoSQL).
        /// Caller must call `defer parsed.deinit()` on the returned parsed struct.
        pub fn find(db: *Db, allocator: std.mem.Allocator, id: anytype) !?std.json.Parsed(Self) {
            var id_buf: [64]u8 = undefined;
            const id_str = idToString(&id_buf, id);

            const doc_opt = try db.findByIdAlloc(tableName(), id_str, allocator);
            const doc = doc_opt orelse return null;
            defer allocator.free(doc);
            return try fromJson(allocator, doc);
        }

        /// Retrieves all records for this model from the database.
        /// Caller owns the returned slice and strings inside it.
        pub fn findAll(db: *Db, allocator: std.mem.Allocator) ![][]const u8 {
            return db.findAll(tableName(), allocator);
        }

        /// Deletes a model instance by ID from the database (SQL or NoSQL).
        pub fn delete(db: *Db, id: anytype) bool {
            var id_buf: [64]u8 = undefined;
            const id_str = idToString(&id_buf, id);
            return db.deleteById(tableName(), id_str);
        }

        /// Returns the total record count for this model's table or collection.
        pub fn count(db: *Db) usize {
            return db.count(tableName());
        }

        /// Creates a fluent query builder to filter, sort, paginate, and query instances of this model.
        pub fn query(db: *Db, allocator: std.mem.Allocator) QueryBuilder(Self) {
            return QueryBuilder(Self).init(db, allocator);
        }

        /// Automatically synchronizes the table/collection schema for this model in the database.
        pub fn sync(db: *Db) !void {
            const ddl = try createTableSql(db.allocator);
            defer db.allocator.free(ddl);
            try db.executeSql(ddl);
        }

        /// Loads all associated records of type TargetModel where TargetModel.<foreign_key> == self.id.
        /// Caller owns the returned slice and must call `defer parsed.deinit()` on each element.
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
        /// Caller must call `defer parsed.deinit()` on the returned parsed struct.
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
