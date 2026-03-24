# ADR-0005: Performance Over Inheritance, Utils Over Heavy Classes

**Date**: 2026-03-24
**Status**: Accepted

## Context

Java projects tend toward deep inheritance hierarchies, dependency injection frameworks, and heavy abstraction layers. The Aya backend handles financial transactions over SBE — a protocol designed for zero-copy, low-latency systems. The code style should match.

## Decision

1. **Favor flat, direct code** over class hierarchies. Duplication is acceptable for clarity and performance.
2. **Use static utility methods and lightweight modules** instead of heavyweight OOP, DI containers, or framework magic.
3. **Follow GC-favorable patterns**: zero-copy with SBE flyweight encoders/decoders, buffer reuse via ThreadLocal or pools, avoid boxing, minimize allocations in hot paths, prefer records for data carriers.
4. **SnakeYAML for all configuration** — one format, no annotation-driven config, no `.properties`, no XML config.

## Consequences

- **Positive**: Faster code, less garbage collection pressure, easier to read and follow, lower latency on the critical request path, simpler dependency graph.
- **Negative**: Some duplication (but duplication is explicit and greppable, whereas the wrong abstraction is hidden and misleading). Less "idiomatic enterprise Java" — developers from Spring-heavy backgrounds may need to adjust.
- **Neutral**: Still uses Java 21+ features (records, sealed classes, pattern matching) — just without the framework overhead.
