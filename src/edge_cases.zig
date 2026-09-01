const std = @import("std");
const zmcp = @import("root.zig");
const testing = std.testing;

const CalculatorTool = struct {
    pub const name = "calculator";
    pub const description = "Add two numbers";
    pub const Params = struct {
        a: f64,
        b: f64,
        operation: []const u8 = "add",
    };

    pub fn call(params: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        if (std.mem.eql(u8, params.operation, "add")) {
            const res = params.a + params.b;
            const res_str = try std.fmt.allocPrint(alloc, "{d}", .{res});
            return zmcp.CallToolResult.text(res_str);
        } else if (std.mem.eql(u8, params.operation, "div")) {
            if (params.b == 0.0) {
                return zmcp.CallToolResult.err("Division by zero");
            }
            const res = params.a / params.b;
            const res_str = try std.fmt.allocPrint(alloc, "{d}", .{res});
            return zmcp.CallToolResult.text(res_str);
        } else {
            return error.UnknownOperation;
        }
    }
};

const NoArgTool = struct {
    pub const name = "status_ping";
    pub const description = "Health status ping without arguments";
    pub const Params = struct {};

    pub fn call(_: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        _ = alloc;
        return zmcp.CallToolResult.text("OK: Healthy");
    }
};

// ============================================================================
// 1. JSON-RPC Protocol & Error Code Tests
// ============================================================================

test "zmcp: malformed JSON returns parse_error (-32700)" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    const resp = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\", missing_quotes");
    defer if (resp) |r| allocator.free(r);

    try testing.expect(resp != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"code\":-32700") != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "Parse error") != null);
}

test "zmcp: invalid request structure returns invalid_request (-32600)" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    // Not an object
    const r1 = try server.handleMessage(allocator, "[\"not\", \"an\", \"object\"]");
    defer if (r1) |r| allocator.free(r);
    try testing.expect(std.mem.indexOf(u8, r1.?, "\"code\":-32600") != null);

    // Missing method
    const r2 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1}");
    defer if (r2) |r| allocator.free(r);
    try testing.expect(std.mem.indexOf(u8, r2.?, "\"code\":-32600") != null);

    // Method not a string
    const r3 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":123}");
    defer if (r3) |r| allocator.free(r);
    try testing.expect(std.mem.indexOf(u8, r3.?, "\"code\":-32600") != null);
}

test "zmcp: unknown method returns method_not_found (-32601)" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    const resp = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":\"req-42\",\"method\":\"non_existent_method\"}");
    defer if (resp) |r| allocator.free(r);

    try testing.expect(resp != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"code\":-32601") != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"id\":\"req-42\"") != null);
}

test "zmcp: notifications return null without response" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    const r1 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
    try testing.expect(r1 == null);

    const r2 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}");
    try testing.expect(r2 == null);

    // Unknown notification without ID returns null
    const r3 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"custom/unhandled_notify\"}");
    try testing.expect(r3 == null);
}

test "zmcp: ping method returns empty result" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    const resp = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"ping\"}");
    defer if (resp) |r| allocator.free(r);

    try testing.expect(resp != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"id\":99") != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"result\":{}") != null);
}

// ============================================================================
// 2. Tool Execution & Error Handling Tests
// ============================================================================

test "zmcp: tools/call invalid params error (-32602)" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    // No params object
    const r1 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\"}");
    defer if (r1) |r| allocator.free(r);
    try testing.expect(std.mem.indexOf(u8, r1.?, "\"code\":-32602") != null);

    // Missing tool name
    const r2 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{}}");
    defer if (r2) |r| allocator.free(r);
    try testing.expect(std.mem.indexOf(u8, r2.?, "\"code\":-32602") != null);
}

test "zmcp: tools/call unregistered tool returns tool_not_found (-32001)" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    const resp = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"missing_tool\"}}");
    defer if (resp) |r| allocator.free(r);

    try testing.expect(resp != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"code\":-32001") != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "Tool not found") != null);
}

test "zmcp: tools/call successful execution and error catching" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    try server.registerTool(CalculatorTool);
    try server.registerTool(NoArgTool);

    // 1. Success tool call
    const r1 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"calculator\",\"arguments\":{\"a\":12.5,\"b\":7.5,\"operation\":\"add\"}}}");
    defer if (r1) |r| allocator.free(r);
    try testing.expect(r1 != null);
    try testing.expect(std.mem.indexOf(u8, r1.?, "\"isError\":false") != null);
    try testing.expect(std.mem.indexOf(u8, r1.?, "20") != null);

    // 2. Application error result from tool (division by zero)
    const r2 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"calculator\",\"arguments\":{\"a\":10,\"b\":0,\"operation\":\"div\"}}}");
    defer if (r2) |r| allocator.free(r);
    try testing.expect(r2 != null);
    try testing.expect(std.mem.indexOf(u8, r2.?, "\"isError\":true") != null);
    try testing.expect(std.mem.indexOf(u8, r2.?, "Division by zero") != null);

    // 3. Zig error thrown from tool handler caught and wrapped
    const r3 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"calculator\",\"arguments\":{\"a\":10,\"b\":2,\"operation\":\"invalid_op\"}}}");
    defer if (r3) |r| allocator.free(r);
    try testing.expect(r3 != null);
    try testing.expect(std.mem.indexOf(u8, r3.?, "\"isError\":true") != null);
    try testing.expect(std.mem.indexOf(u8, r3.?, "Tool execution failed: UnknownOperation") != null);

    // 4. Zero-argument tool
    const r4 = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"status_ping\"}}");
    defer if (r4) |r| allocator.free(r);
    try testing.expect(r4 != null);
    try testing.expect(std.mem.indexOf(u8, r4.?, "OK: Healthy") != null);
}

test "zmcp: tools/list returns complete schema definitions" {
    const allocator = testing.allocator;
    var server = zmcp.Server.init(allocator, .{ .name = "test-srv", .version = "1.0.0" });
    defer server.deinit();

    try server.registerTool(CalculatorTool);
    try server.registerTool(NoArgTool);

    const resp = try server.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":\"list-1\",\"method\":\"tools/list\"}");
    defer if (resp) |r| allocator.free(r);

    try testing.expect(resp != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"name\":\"calculator\"") != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"name\":\"status_ping\"") != null);
    try testing.expect(std.mem.indexOf(u8, resp.?, "\"inputSchema\"") != null);
}
