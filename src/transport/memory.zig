const std = @import("std");
const Allocator = std.mem.Allocator;
const Server = @import("../server.zig").Server;

/// In-memory transport for deterministic testing and embedded execution
pub const MemoryTransport = struct {
    server: *Server,
    allocator: Allocator,

    pub fn init(allocator: Allocator, server: *Server) MemoryTransport {
        return .{
            .allocator = allocator,
            .server = server,
        };
    }

    pub fn send(self: *MemoryTransport, request_json: []const u8) !?[]u8 {
        return self.server.handleMessage(self.allocator, request_json);
    }
};
