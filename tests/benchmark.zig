const std = @import("std");
const zmcp = @import("zmcp");

const EchoTool = struct {
    pub const name = "echo";
    pub const description = "Echo tool for benchmarking";
    pub const Params = struct {
        msg: []const u8,
        count: u32 = 1,
    };

    pub fn call(params: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        _ = alloc;
        return zmcp.CallToolResult.text(params.msg);
    }
};

fn getMonotonicNs() u64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var srv = zmcp.Server.init(allocator, .{
        .name = "bench-server",
        .version = "1.0.0",
    });
    defer srv.deinit();

    try srv.registerTool(EchoTool);

    var transport = zmcp.MemoryTransport.init(allocator, &srv);

    const call_req = "{\"jsonrpc\":\"2.0\",\"id\":100,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{\"msg\":\"hello world\",\"count\":5}}}";

    // 1. Warmup
    var w: usize = 0;
    while (w < 10_000) : (w += 1) {
        if (try transport.send(call_req)) |resp| {
            allocator.free(resp);
        }
    }

    // 2. Measure
    const total_iterations: usize = 200_000;
    const start_ns = getMonotonicNs();

    var i: usize = 0;
    while (i < total_iterations) : (i += 1) {
        if (try transport.send(call_req)) |resp| {
            allocator.free(resp);
        }
    }

    const end_ns = getMonotonicNs();
    const elapsed_ns = end_ns - start_ns;
    const elapsed_sec = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(total_iterations)) / elapsed_sec;
    const latency_ns = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(total_iterations));

    std.debug.print("\n=== zmcp Benchmark Highlights (ReleaseFast, {d} runs) ===\n", .{total_iterations});
    std.debug.print("• Total Time   : {d:.4} s\n", .{elapsed_sec});
    std.debug.print("• Throughput   : {d:.2} ops/sec ({d:.2}k req/sec)\n", .{ ops_per_sec, ops_per_sec / 1000.0 });
    std.debug.print("• Latency      : {d:.2} ns/op ({d:.3} µs/op)\n\n", .{ latency_ns, latency_ns / 1000.0 });
}
