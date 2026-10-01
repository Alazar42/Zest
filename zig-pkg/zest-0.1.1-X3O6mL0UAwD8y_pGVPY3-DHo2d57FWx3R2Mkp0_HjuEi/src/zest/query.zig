const std = @import("std");
const Db = @import("db.zig");

pub const QueryOp = enum {
    eq,
    neq,
    contains,
    gt,
    gte,
    lt,
    lte,
};

pub const SortOrder = enum {
    asc,
    desc,
};

pub const Condition = struct {
    field: []const u8,
    op: QueryOp,
    val_str: []const u8,
    val_num: ?f64 = null,
};

/// Fluent query builder for models working seamlessly across SQL and NoSQL.
pub fn QueryBuilder(comptime ModelType: type) type {
    return struct {
        db: *Db,
        allocator: std.mem.Allocator,
        conditions: std.ArrayList(Condition),
        order_field: ?[]const u8 = null,
        order_dir: SortOrder = .asc,
        limit_val: ?usize = null,
        offset_val: usize = 0,

        const Self = @This();

        pub fn init(db: *Db, allocator: std.mem.Allocator) Self {
            return .{
                .db = db,
                .allocator = allocator,
                .conditions = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.conditions.items) |c| {
                self.allocator.free(c.field);
                self.allocator.free(c.val_str);
            }
            self.conditions.deinit(self.allocator);
            if (self.order_field) |f| {
                self.allocator.free(f);
            }
        }

        /// Adds a filter condition on a string field.
        pub fn where(self: *Self, field: []const u8, op: QueryOp, value: []const u8) *Self {
            const f_dup = self.allocator.dupe(u8, field) catch return self;
            const v_dup = self.allocator.dupe(u8, value) catch return self;
            const num = std.fmt.parseFloat(f64, value) catch null;
            self.conditions.append(self.allocator, .{
                .field = f_dup,
                .op = op,
                .val_str = v_dup,
                .val_num = num,
            }) catch {};
            return self;
        }

        /// Adds an equality condition.
        pub fn whereEql(self: *Self, field: []const u8, value: []const u8) *Self {
            return self.where(field, .eq, value);
        }

        /// Adds a filter condition on a numeric field.
        pub fn whereNum(self: *Self, field: []const u8, op: QueryOp, value: anytype) *Self {
            var buf: [64]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return self;
            return self.where(field, op, str);
        }

        /// Sets the sort field and direction.
        pub fn orderBy(self: *Self, field: []const u8, order: SortOrder) *Self {
            if (self.order_field) |f| self.allocator.free(f);
            self.order_field = self.allocator.dupe(u8, field) catch null;
            self.order_dir = order;
            return self;
        }

        /// Sets the maximum number of results to return.
        pub fn limit(self: *Self, max_rows: usize) *Self {
            self.limit_val = max_rows;
            return self;
        }

        /// Sets the number of results to skip.
        pub fn offset(self: *Self, skip_rows: usize) *Self {
            self.offset_val = skip_rows;
            return self;
        }

        fn extractField(doc: []const u8, field: []const u8) ?[]const u8 {
            var key_buf: [128]u8 = undefined;
            const key_pattern = std.fmt.bufPrint(&key_buf, "\"{s}\":", .{field}) catch return null;
            const pos = std.mem.indexOf(u8, doc, key_pattern) orelse return null;
            var val_start = pos + key_pattern.len;
            while (val_start < doc.len and (doc[val_start] == ' ' or doc[val_start] == '\t')) : (val_start += 1) {}
            if (val_start >= doc.len) return null;

            if (doc[val_start] == '"') {
                const inner_start = val_start + 1;
                const end = std.mem.indexOfScalar(u8, doc[inner_start..], '"') orelse return null;
                return doc[inner_start .. inner_start + end];
            } else {
                var end = val_start;
                while (end < doc.len and doc[end] != ',' and doc[end] != '}' and doc[end] != ']' and doc[end] != ' ' and doc[end] != '\n' and doc[end] != '\r') : (end += 1) {}
                return doc[val_start..end];
            }
        }

        fn matchesConditions(self: *const Self, doc: []const u8) bool {
            for (self.conditions.items) |cond| {
                const val = extractField(doc, cond.field) orelse return false;

                if (cond.val_num) |target_num| {
                    if (std.fmt.parseFloat(f64, val)) |doc_num| {
                        const matched = switch (cond.op) {
                            .eq => doc_num == target_num,
                            .neq => doc_num != target_num,
                            .gt => doc_num > target_num,
                            .gte => doc_num >= target_num,
                            .lt => doc_num < target_num,
                            .lte => doc_num <= target_num,
                            .contains => std.mem.indexOf(u8, val, cond.val_str) != null,
                        };
                        if (!matched) return false;
                        continue;
                    } else |_| {}
                }

                const matched = switch (cond.op) {
                    .eq => std.mem.eql(u8, val, cond.val_str),
                    .neq => !std.mem.eql(u8, val, cond.val_str),
                    .contains => std.mem.indexOf(u8, val, cond.val_str) != null,
                    .gt => std.mem.order(u8, val, cond.val_str) == .gt,
                    .gte => std.mem.order(u8, val, cond.val_str) != .lt,
                    .lt => std.mem.order(u8, val, cond.val_str) == .lt,
                    .lte => std.mem.order(u8, val, cond.val_str) != .gt,
                };
                if (!matched) return false;
            }
            return true;
        }

        /// Executes the query and returns the matching JSON documents.
        /// Caller owns the returned slice and each string in it.
        pub fn execJson(self: *Self) ![][]const u8 {
            defer self.deinit();

            const table_name = ModelType.model.tableName();
            const all = try self.db.findAll(table_name, self.allocator);
            defer {
                for (all) |doc| self.allocator.free(doc);
                self.allocator.free(all);
            }

            var matched: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (matched.items) |m| self.allocator.free(m);
                matched.deinit(self.allocator);
            }

            var skipped: usize = 0;
            for (all) |doc| {
                if (!self.matchesConditions(doc)) continue;

                if (skipped < self.offset_val) {
                    skipped += 1;
                    continue;
                }

                if (self.limit_val) |lim| {
                    if (matched.items.len >= lim) break;
                }

                const duped = try self.allocator.dupe(u8, doc);
                try matched.append(self.allocator, duped);
            }

            return matched.toOwnedSlice(self.allocator);
        }

        /// Executes the query and returns an array of parsed model instances.
        /// Caller owns the returned slice and must call `defer parsed.deinit()` on each element.
        pub fn exec(self: *Self) ![]std.json.Parsed(ModelType) {
            const raw_docs = try self.execJson();
            defer {
                for (raw_docs) |d| self.allocator.free(d);
                self.allocator.free(raw_docs);
            }

            var list: std.ArrayList(std.json.Parsed(ModelType)) = .empty;
            errdefer {
                for (list.items) |*p| p.deinit();
                list.deinit(self.allocator);
            }

            for (raw_docs) |doc| {
                const parsed = try ModelType.model.fromJson(self.allocator, doc);
                try list.append(self.allocator, parsed);
            }

            return list.toOwnedSlice(self.allocator);
        }

        /// Returns the first matching record or null if not found.
        pub fn first(self: *Self) !?std.json.Parsed(ModelType) {
            _ = self.limit(1);
            const list = try self.exec();
            defer self.allocator.free(list);

            if (list.len == 0) return null;
            return list[0];
        }

        /// Returns the count of records matching the query.
        pub fn count(self: *Self) !usize {
            const docs = try self.execJson();
            defer {
                for (docs) |d| self.allocator.free(d);
                self.allocator.free(docs);
            }
            return docs.len;
        }
    };
}
