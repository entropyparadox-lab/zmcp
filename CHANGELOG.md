# Changelog

## 1.1.1 — 2026-11-09

- Target Zig 0.17.1 in the package manifest, CI, and documentation; patch update
  from 1.1.0 with no public library API changes.
- Add a bounded real stdio smoke covering initialization, notification silence,
  tool discovery, successful and failed tool calls, and a 256 KiB pipe round trip.
- Include examples and benchmarks/tests in package `.paths`, so dependency
  consumers can evaluate the complete build graph from fetched archives.
- Update example metadata, add a Korean guide, and document exact-commit pins
  without assuming an unpublished release tag exists.
