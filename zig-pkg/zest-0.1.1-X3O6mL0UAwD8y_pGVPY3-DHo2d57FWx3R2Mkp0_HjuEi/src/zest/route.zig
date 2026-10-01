const std = @import("std");
const Request = @import("request.zig");
const Response = @import("response.zig");

const middleware = @import("middleware.zig");
pub const MiddlewareFn = middleware.MiddlewareFn;

pub const HandlerFn = *const fn (req: *Request, res: *Response) anyerror!void;

method: std.http.Method,
path: []const u8,
handler: HandlerFn,
middlewares: []const MiddlewareFn = &.{},

const Self = @This();

/// Automatically wraps any supported handler signature into a standard HandlerFn.
/// Supported signatures:
/// - `fn (res: *Response) !void`
/// - `fn (req: *Request) !void`
/// - `fn (req: *Request, res: *Response) !void`
/// - `fn (res: *Response, req: *Request) !void`
/// - `fn () !void`
/// Handlers can return `void` or any error union `!void`.
pub fn wrap(comptime handler: anytype) HandlerFn {
    const H = @TypeOf(handler);
    const info = @typeInfo(H);
    if (info != .@"fn") {
        @compileError("Route handler must be a function, found " ++ @typeName(H));
    }
    const fn_info = info.@"fn";

    return struct {
        fn wrapper(req: *Request, res: *Response) anyerror!void {
            if (fn_info.params.len == 0) {
                return callHandler(handler, .{});
            } else if (fn_info.params.len == 1) {
                const P0 = fn_info.params[0].type orelse @compileError("Handler parameter must have a known type");
                if (P0 == *Response) {
                    return callHandler(handler, .{res});
                } else if (P0 == *Request) {
                    return callHandler(handler, .{req});
                } else {
                    @compileError("Single-parameter handler must take *Response or *Request, found " ++ @typeName(P0));
                }
            } else if (fn_info.params.len == 2) {
                const P0 = fn_info.params[0].type orelse @compileError("Handler parameter must have a known type");
                const P1 = fn_info.params[1].type orelse @compileError("Handler parameter must have a known type");
                if (P0 == *Request and P1 == *Response) {
                    return callHandler(handler, .{ req, res });
                } else if (P0 == *Response and P1 == *Request) {
                    return callHandler(handler, .{ res, req });
                } else {
                    @compileError("Two-parameter handler must take (*Request, *Response) or (*Response, *Request)");
                }
            } else {
                @compileError("Handler can take at most 2 parameters (req, res)");
            }
        }

        inline fn callHandler(func: anytype, args: anytype) !void {
            const ret = @call(.auto, func, args);
            const RetType = @TypeOf(ret);
            if (@typeInfo(RetType) == .error_union) {
                return try ret;
            }
        }
    }.wrapper;
}
