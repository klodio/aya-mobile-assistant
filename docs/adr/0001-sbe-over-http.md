# ADR-0001: SBE Over HTTP for Client-Server Protocol

**Date**: 2026-03-24
**Status**: Accepted

## Context

The Aya mobile wallet needs a wire protocol for communicating with the backend. Options considered: JSON over HTTP, Protocol Buffers (gRPC), FlatBuffers, Cap'n Proto, and SBE.

The team already uses SBE extensively for the Aya Trade exchange, including at the frontend interface level.

## Decision

Use Simple Binary Encoding (SBE) over HTTP for all client-server communication. A single XML schema (`aya-assistant.xml`) produces Java server codecs and TypeScript React Native client codecs via code generation.

WebSocket with SBE-framed binary messages for streaming (Phase 2).

## Consequences

- **Positive**: Type safety, no ambiguity, compact binary on mobile networks, code generation eliminates serialization bugs, versioning via additive-only schema evolution, team has SBE expertise from the exchange.
- **Negative**: SBE is uncommon for mobile assistant protocols — harder to debug without tooling (mitigated by CLI client's `/raw` mode), fewer community examples, TypeScript SBE codegen ecosystem is less mature than Java.
- **Neutral**: Requires the CLI test client for manual testing (can't use curl like with JSON).
