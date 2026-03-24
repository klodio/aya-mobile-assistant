# ADR-0002: SQLite + Redis as Only Storage

**Date**: 2026-03-24
**Status**: Accepted

## Context

The backend needs persistent storage (ABI/IDL cache, conversation history, token registry) and ephemeral storage (session state, rate limiting, caching). Options: PostgreSQL, MySQL, MongoDB, or simpler alternatives.

## Decision

Use SQLite (embedded) for all persistent data and Redis (managed externally) as the only external service. No Docker, no external database servers.

## Consequences

- **Positive**: Zero-config SQLite (created on first run), single fat JAR deployment, no database server to manage, Redis is the only external dependency and can be managed/hosted.
- **Negative**: SQLite is per-instance (not shared across horizontal instances) — mitigated by Redis for shared state and the fact that SQLite data (ABI cache) is safe to duplicate. Write concurrency is limited in SQLite — mitigated by WAL mode and the fact that writes are infrequent.
- **Neutral**: Horizontal scaling works via shared Redis; SQLite acts as a local cache per instance.
