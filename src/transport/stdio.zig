const std = @import("std");
const Allocator = std.mem.Allocator;
const Server = @import("../server.zig").Server;

/// Runs the MCP Server listening on standard input and writing to standard output (newline-delimited JSON-RPC).
pub fn run(server: *Server, allocator: Allocator) !void {
    const stdin_fd = std.posix.STDIN_FILENO;
    const stdout_fd = std.posix.STDOUT_FILENO;

    var read_buf: [65536]u8 = undefined;
    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(allocator);

    while (true) {
        const bytes_read = std.posix.read(stdin_fd, &read_buf) catch |err| {
            if (err == error.WouldBlock) continue;
            break;
        };
        if (bytes_read == 0) break; // EOF

        for (read_buf[0..bytes_read]) |byte| {
            if (byte == '\n') {
                const line = std.mem.trim(u8, line_buf.items, " \r\t");
                if (line.len > 0) {
                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const arena_alloc = arena.allocator();

                    if (try server.handleMessage(arena_alloc, line)) |resp| {
                        _ = try std.posix.write(stdout_fd, resp);
                        _ = try std.posix.write(stdout_fd, "\n");
                    }
                }
                line_buf.clearRetainingCapacity();
            } else {
                try line_buf.append(allocator, byte);
            }
        }
    }
}
