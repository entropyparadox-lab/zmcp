# zmcp ⚡

[![Zig Version](https://img.shields.io/badge/Zig-0.16.0%2B-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Zero-Allocation](https://img.shields.io/badge/Zero--Copy-Comptime%20Schema-brightgreen.svg)]()
[![Model Context Protocol](https://img.shields.io/badge/MCP-2024--11--05-purple.svg)](https://modelcontextprotocol.io)

**Pure Zig Zero-Allocation Model Context Protocol (MCP) SDK & Comptime Tool Generator (v0.16.0+)**

`zmcp` provides native, ultra-lightweight, zero-C-dependency Model Context Protocol (MCP) server infrastructure for Zig developers. By leveraging Zig's compile-time reflection (`@typeInfo`), `zmcp` automatically converts plain Zig structs into **Draft-7 JSON Schema** definitions and dispatches **JSON-RPC 2.0 requests** at native speed with minimal memory footprint.

---

## Benchmark Highlights (AMD Ryzen / ReleaseFast, 200,000 runs)

| Scenario | Throughput (req/sec) | Latency (µs/op) | Memory Overhead |
| :--- | :--- | :--- | :--- |
| **Full Tool Call & Schema Dispatch** | **325,000 ops/sec** | **3.07 µs** | **0 Leaks (Per-request Arena)** |

---

## Key Features

- 🚀 **Comptime JSON Schema Generator (`@typeInfo`)**: Automatically generates valid Draft-7 JSON Schema from arbitrary Zig structs without runtime overhead.
- 🎯 **Declarative Tool Metadata (`pub const zmcp = .{ ... }`)**:
  - Field-level documentation strings mapped directly to Schema descriptions.
  - Automatic detection of optional fields and default values for schema `required` arrays.
- 🌳 **Full MCP Specification (2024-11-05)**:
  - `initialize`, `notifications/initialized`, `ping`
  - `tools/list`, `tools/call`
  - `resources/list`, `resources/read`
  - `prompts/list`
- 🛡️ **Zero-C Dependencies & Pure Zig 0.16.0+**: Built natively with standard library and POSIX syscalls.
- 🔌 **Transports**:
  - **Stdio (`zmcp.stdio.run`)**: Standard input/output transport for AI agents (Hermes, Claude Code, Cursor).
  - **Memory (`zmcp.MemoryTransport`)**: High-speed in-memory transport for deterministic testing and embedded runtimes.

---

## Installation (`build.zig.zon`)

Add `zmcp` to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/entropyparadox-lab/zmcp/archive/refs/tags/v1.0.0.tar.gz
```

In your `build.zig`:

```zig
const zmcp_dep = b.dependency("zmcp", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zmcp", zmcp_dep.module("zmcp"));
```

---

## Quickstart (Building an MCP Server in 30 Seconds)

```zig
const std = @import("std");
const zmcp = @import("zmcp");

// 1. Define a strongly-typed tool
const CalculateTool = struct {
    pub const name = "calculate";
    pub const description = "Add two numbers together";

    pub const Params = struct {
        a: f64,
        b: f64,
        pub const zmcp = .{
            .help = .{
                .a = "First number operand",
                .b = "Second number operand",
            },
        };
    };

    pub fn call(params: Params, alloc: std.mem.Allocator) !zmcp.CallToolResult {
        const sum = params.a + params.b;
        const msg = try std.fmt.allocPrint(alloc, "Sum is: {d}", .{sum});
        return zmcp.CallToolResult.text(msg);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var srv = zmcp.Server.init(allocator, .{
        .name = "my-mcp-server",
        .version = "1.0.0",
        .instructions = "Native Zig MCP Server",
    });
    defer srv.deinit();

    // 2. Register tool (schema is synthesized at compile-time)
    try srv.registerTool(CalculateTool);

    // 3. Start Stdio transport
    try zmcp.stdio.run(&srv, allocator);
}
```

---

## License

MIT License (c) 2026 Entropy Paradox Lab / Charles Choi
