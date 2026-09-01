const std = @import("std");

pub const protocol = @import("protocol.zig");
pub const schema = @import("schema.zig");
pub const server = @import("server.zig");
pub const stdio = @import("transport/stdio.zig");
pub const memory = @import("transport/memory.zig");

// Re-exports
pub const Server = server.Server;
pub const RequestId = protocol.RequestId;
pub const ErrorCode = protocol.ErrorCode;
pub const CallToolResult = protocol.CallToolResult;
pub const ToolDefinition = protocol.ToolDefinition;
pub const ResourceDefinition = protocol.ResourceDefinition;
pub const ResourceContents = protocol.ResourceContents;
pub const PromptDefinition = protocol.PromptDefinition;
pub const PromptArgument = protocol.PromptArgument;
pub const PromptMessage = protocol.PromptMessage;
pub const ServerInfo = protocol.ServerInfo;
pub const MemoryTransport = memory.MemoryTransport;

pub const generateSchemaJson = schema.generateSchemaJson;

test "end-to-end mcp server lifecycle with memory transport" {
    const allocator = std.testing.allocator;

    var srv = Server.init(allocator, .{
        .name = "test-zig-mcp",
        .version = "1.0.0",
        .instructions = "Test instructions for agent",
    });
    defer srv.deinit();

    // Define a typed tool
    const AddTool = struct {
        pub const name = "add";
        pub const description = "Add two numbers together";
        pub const Params = struct {
            a: i64,
            b: i64,
            pub const zmcp = .{
                .help = .{
                    .a = "First integer",
                    .b = "Second integer",
                },
            };
        };

        pub fn call(params: Params, alloc: std.mem.Allocator) !CallToolResult {
            const sum = params.a + params.b;
            const res_str = try std.fmt.allocPrint(alloc, "Result is {d}", .{sum});
            return CallToolResult.text(res_str);
        }
    };

    try srv.registerTool(AddTool);

    var client = MemoryTransport.init(allocator, &srv);

    // 1. Initialize
    const init_req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test-client\",\"version\":\"1.0\"}}}";
    const init_resp = (try client.send(init_req)).?;
    defer allocator.free(init_resp);

    try std.testing.expect(std.mem.indexOf(u8, init_resp, "\"test-zig-mcp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, init_resp, "\"2024-11-05\"") != null);

    // 2. Initialized notification (no response)
    const notify_req = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}";
    const notify_resp = try client.send(notify_req);
    try std.testing.expect(notify_resp == null);

    // 3. Ping
    const ping_req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}";
    const ping_resp = (try client.send(ping_req)).?;
    defer allocator.free(ping_resp);
    try std.testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}", ping_resp);

    // 4. Tools list
    const list_req = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}";
    const list_resp = (try client.send(list_req)).?;
    defer allocator.free(list_resp);

    try std.testing.expect(std.mem.indexOf(u8, list_resp, "\"name\":\"add\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_resp, "\"type\":\"integer\"") != null);

    // 5. Call Tool (add 40 + 2 = 42)
    const call_req = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"add\",\"arguments\":{\"a\":40,\"b\":2}}}";
    const call_resp = (try client.send(call_req)).?;
    defer allocator.free(call_resp);

    try std.testing.expect(std.mem.indexOf(u8, call_resp, "Result is 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, call_resp, "\"isError\":false") != null);

    // 6. Call Unknown Tool
    const bad_tool_req = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"non_existent\",\"arguments\":{}}}";
    const bad_tool_resp = (try client.send(bad_tool_req)).?;
    defer allocator.free(bad_tool_resp);

    try std.testing.expect(std.mem.indexOf(u8, bad_tool_resp, "\"code\":-32001") != null);
}

test {
    _ = protocol;
    _ = schema;
    _ = server;
    _ = stdio;
    _ = memory;
    _ = @import("edge_cases.zig");
}
