# ADR-0002: SQLite + In-Memory State (Optional Redis)

**Date**: 2026-03-24
**Status**: Accepted (supersedes original "SQLite + Redis as Only Storage")

## Context

The backend needs persistent storage (ABI/IDL cache, conversation history, token registry) and ephemeral storage (session state, rate limiting, caching). The original design required Redis as the only external service. However, requiring Redis adds operational overhead for simple deployments (single instance, development, testing) where in-memory state is sufficient.

## Decision

Use SQLite (embedded) for all persistent data and an in-memory StateStore by default for ephemeral state. Redis is an **optional** backend for the StateStore, enabled via `state.backend: redis`, intended for horizontal scaling where shared state across instances is needed.

- **Default** (`state.backend: memory`): Zero external dependencies. Session state, rate limiting, and caching live in-process using `ConcurrentHashMap` with TTL-based eviction. Suitable for single-instance deployments.
- **Optional** (`state.backend: redis`): Redis provides shared session state, rate limiting, and caching across multiple instances. Required only when running multiple backend instances behind a load balancer.

## Consequences

- **Positive**: Zero-config deployment — `java -jar aya-backend.jar` works with no external services. SQLite is created on first run. Development and testing require no infrastructure setup. Single-instance production deployments need only a JDK.
- **Positive**: Horizontal scaling is still fully supported by opting into Redis via a single config flag.
- **Negative**: In-memory state is lost on restart (mitigated by SQLite persistence for conversation history; sessions expire after 24h regardless). With the in-memory backend, sticky sessions are required for multi-instance setups (or just use Redis).
- **Neutral**: The StateStore abstraction adds a thin interface layer, but keeps the rest of the codebase unaware of the backing implementation.
