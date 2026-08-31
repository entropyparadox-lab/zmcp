const std = @import("std");
const zmcp = @import("zmcp");

// 1. Tool: Add
const AddTool = struct {
    pub const name = "add";
    pub const description = "Add two numbers together";
    pub const Params = struct {
        a: f64,
        b: f64,
        pub const zmcp = .{
            .help = .{
                .a = "First operand",
                .b = "Second operand",
            },
        };
    };

    pub fn call(params: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        const sum = params.a + params.b;
        const res_str = try std.fmt.allocPrint(alloc, "Sum: {d}", .{sum});
        return zmcp.CallToolResult.text(res_str);
    }
};

// 2. Tool: Reverse String
const ReverseTool = struct {
    pub const name = "reverse_string";
    pub const description = "Reverse an input string and optionally uppercase it";
    pub const Params = struct {
        text: []const u8,
        uppercase: bool = false,
        pub const zmcp = .{
            .help = .{
                .text = "The string to reverse",
                .uppercase = "Whether to convert to uppercase",
            },
        };
    };

    pub fn call(params: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        const reversed = try alloc.alloc(u8, params.text.len);
        for (params.text, 0..) |c, i| {
            reversed[params.text.len - 1 - i] = if (params.uppercase) std.ascii.toUpper(c) else c;
        }
        return zmcp.CallToolResult.text(reversed);
    }
};

// 3. Tool: System Status
const SystemStatusTool = struct {
    pub const name = "system_status";
    pub const description = "Get native Zig runtime and system status";
    pub const Params = struct {};

    pub fn call(params: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        _ = params;
        const status = try std.fmt.allocPrint(alloc, "zmcp Server v1.0.0 (Pure Zig 0.16.0+, Zero-Alloc Engine)", .{});
        return zmcp.CallToolResult.text(status);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var srv = zmcp.Server.init(allocator, .{
        .name = "zig-native-mcp",
        .version = "1.0.0",
        .instructions = "Native Zig 0.16.0 Model Context Protocol Tool Server",
    });
    defer srv.deinit();

    try srv.registerTool(AddTool);
    try srv.registerTool(ReverseTool);
    try srv.registerTool(SystemStatusTool);

    // Run stdio loop
    try zmcp.stdio.run(&srv, allocator);
}
