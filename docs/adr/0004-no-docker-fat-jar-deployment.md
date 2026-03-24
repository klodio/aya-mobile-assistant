# ADR-0004: No Docker, Fat JAR Deployment

**Date**: 2026-03-24
**Status**: Accepted

## Context

The backend needs a deployment model. Industry convention leans toward Docker containers, but the team values simplicity and minimal operational overhead.

## Decision

Deploy as a single fat JAR. No Docker, no Kubernetes, no container orchestration. Prerequisites: JDK 21+ and a Redis instance. Run with `java -jar aya-backend.jar`.

## Consequences

- **Positive**: Simplest possible deployment. No container layer to debug. No image registry to manage. No Docker-in-Docker for CI. Fast startup. Easy to run locally for development.
- **Negative**: No container isolation — must manage JDK version on the host. No built-in resource limits (must use JVM flags or OS-level cgroups if needed). Horizontal scaling requires a load balancer configured manually.
- **Neutral**: The CLI test client also deploys as a fat JAR, maintaining consistency.
