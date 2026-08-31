# Contributing to zmcp ⚡

Thank you for contributing to `zmcp`! To maintain the highest reliability, performance, and community trust in the Zig ecosystem, we follow strict quality guidelines.

---

## 1. Compiler Versioning & Branch Strategy

* **`main` (Protected)**: Targets **Official Stable Zig (`0.16.x`)**. All production releases (`vX.Y.Z`) are cut exclusively from `main`.
* **`zig-master`**: Tracks upstream `ziglang/zig` nightly builds.
* **`feat/<name>` / `fix/<name>`**: Branch off `main` for stable changes.

---

## 2. Strict Quality & Verification Gate

1. **100% Tested & Verified**: Every PR must include reproducible test coverage (`zig build test`).
2. **Zero-Allocation Invariant**: Comptime schema synthesis and per-request arena dispatching must ensure 0 memory leaks across all MCP operations.
3. **No Regressions**: Benchmark throughput (`zig build bench`) must sustain >300k req/s.

---

## 3. Fast Local Development & Git Hooks

Install local pre-commit hooks:
```bash
./scripts/setup-hooks.sh
```

Before opening a PR, run full local verification:
```bash
# 1. Format code
zig fmt src/ examples/ tests/ build.zig

# 2. Run tests
zig build test

# 3. Run example server
zig build run-example

# 4. Verify benchmark
zig build bench
```

---

## 4. Immutable Release & SemVer Policy

* **Semantic Versioning (SemVer 2.0.0)**:
  * `PATCH (1.0.X)`: Bug fixes, MCP protocol edge cases, documentation.
  * `MINOR (1.X.0)`: New transports, new MCP capabilities, backwards-compatible additions.
  * `MAJOR (X.0.0)`: Breaking API changes.
* **Tag Immutability Principle**:
  * Never modify or delete a published Git tag.
