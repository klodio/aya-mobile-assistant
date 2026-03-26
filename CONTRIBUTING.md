# Aya — Developer Rules

These rules are non-negotiable. Every contributor must follow them.

---

## 1. No Docker

Aya deploys as a single fat JAR. No Dockerfiles, no docker-compose, no container orchestration. If you need the backend running, it's `java -jar aya-backend.jar`. No external services required by default. Redis is optional — only install it if you need horizontal scaling (`state.backend: redis`).

## 2. Performance Over Inheritance

Favor flat, direct code over deep class hierarchies. Duplication is acceptable — and often preferable — when it buys clarity and performance.

**Do this:**
```java
// Direct, clear, no virtual dispatch
public static byte[] encodeSwapTransaction(SwapParams params) {
    // flat, obvious logic
}

public static byte[] encodeStakeTransaction(StakeParams params) {
    // similar but different — that's fine
}
```

**Not this:**
```java
// Deep hierarchy, hard to follow, virtual dispatch overhead
abstract class AbstractTransactionEncoder<T extends TransactionParams> {
    protected abstract void encodeSpecific(T params, ByteBuffer buffer);
    // ... 200 lines of "framework"
}

class SwapTransactionEncoder extends AbstractTransactionEncoder<SwapParams> { ... }
class StakeTransactionEncoder extends AbstractTransactionEncoder<StakeParams> { ... }
```

When in doubt between DRY and clarity, choose clarity.

## 3. Libraries and Utils Over Heavy Classes

Prefer static utility methods and lightweight modules. Avoid heavyweight OOP abstractions, deep injection chains, and framework magic.

**Do this:**
```java
public final class SbeCodec {
    private SbeCodec() {}
    public static byte[] encode(UserMessage msg) { ... }
    public static AssistantResponse decode(byte[] bytes) { ... }
}
```

**Not this:**
```java
@Component
@Singleton
public class SbeCodecService implements CodecServiceInterface {
    @Inject private CodecFactory factory;
    @Inject private CodecRegistry registry;
    // ...
}
```

## 4. GC-Favorable Patterns

This project handles financial transactions over SBE — a protocol designed for zero-copy, low-latency systems. The code should match.

- **Zero-copy where possible**: SBE's flyweight pattern encodes/decodes directly on a buffer. Don't copy data into intermediate objects unnecessarily.
- **Reuse buffers**: Use `ThreadLocal<ByteBuffer>` or buffer pools for hot paths (SBE encode/decode, HTTP request/response).
- **Avoid boxing**: Use primitive types. No `Integer` where `int` works. No `Map<String, Object>` for structured data — use records or typed objects.
- **Minimize allocations in hot paths**: Pre-allocate where possible. Avoid `String.format()` in request paths — use `StringBuilder` or pre-built strings.
- **Prefer records over classes** for data carriers (Java records are final, compact, allocation-efficient).

## 5. Keep Specs Up to Date

The specs ([SPEC.md](SPEC.md), [ARCHITECTURE.md](ARCHITECTURE.md), [BEHAVIORS_AND_EXPECTATIONS.md](BEHAVIORS_AND_EXPECTATIONS.md), and their CLI counterparts) are living documents. When code changes, the spec changes in the same PR.

- Added a new tool? Update SPEC.md Section 8 and the tool table in Section 4.4.
- Changed the SBE schema? Update SPEC.md Section 3.
- Modified behavior? Update BEHAVIORS_AND_EXPECTATIONS.md and the relevant feature files.

A PR that changes behavior without updating specs will be rejected.

## 6. SnakeYAML Configuration

All configuration uses YAML via SnakeYAML. One format, everywhere.

- Backend: `application.yml`
- CLI client: `~/.aya-cli/config.yml`
- Portfolio profiles: YAML (not JSON — despite the current `.json` extension, migrate to `.yml`)
- Test fixtures: YAML

No `.properties` files. No XML configuration (SBE schema XML is the exception — that's a protocol definition, not config). No annotation-driven config magic.

```yaml
# application.yml — the one config file
server:
  port: 8080

state:
  backend: memory                    # 'memory' (default) or 'redis' (for horizontal scaling)

# redis:                             # Only needed if state.backend is 'redis'
#   url: redis://localhost:6379

llm:
  providers:
    - name: anthropic
      tier: fast
      apiKey: ${ANTHROPIC_API_KEY}
    - name: openai
      tier: powerful
      apiKey: ${OPENAI_API_KEY}

coingecko:
  pro:
    enabled: true
    apiKey: ${COINGECKO_PRO_API_KEY}
    baseUrl: https://pro-api.coingecko.com/api/v3
  free:
    enabled: true
    baseUrl: https://api.coingecko.com/api/v3

rpc:
  ethereum:
    url: ${ETH_RPC_URL}
  polygon:
    url: ${POLYGON_RPC_URL}
  solana:
    url: ${SOLANA_RPC_URL}

sqlite:
  path: ./aya.db
```

Every setting can be overridden via:
1. **CLI args**: `--coingecko.pro.apiKey=CG-xxx` (highest precedence)
2. **Env vars**: `COINGECKO_PRO_API_KEY=CG-xxx`
3. **YAML file**: lowest precedence, for non-secret defaults

Environment variable substitution (`${VAR}`) is supported in YAML values. Secrets (API keys) should always come from environment variables or CLI args, never hardcoded in YAML. See [application.yml.example](application.yml.example) for the full reference.

## 7. Architecture Decision Records (ADRs)

Any large change — new module, protocol change, new external dependency, architectural pattern shift — requires an ADR.

ADRs live in `docs/adr/` and follow this format:

```
docs/adr/
  0001-sbe-over-http.md
  0002-sqlite-over-postgres.md
  0003-llm-native-agent-design.md
  ...
```

Each ADR:

```markdown
# ADR-NNNN: Title

**Date**: YYYY-MM-DD
**Status**: Accepted | Superseded by ADR-XXXX | Deprecated

## Context
What is the problem or decision we're facing?

## Decision
What did we decide?

## Consequences
What are the trade-offs? What becomes easier? What becomes harder?
```

ADRs are immutable once accepted. If a decision is reversed, write a new ADR that supersedes the old one. Never edit an accepted ADR.

## 8. No Bugfix Without Tests

Every bugfix PR must include a test that:

1. **Reproduces the bug** — the test fails without the fix
2. **Passes with the fix** — proves the fix works
3. **Prevents regression** — the test stays in the suite permanently

No exceptions. If you can't write a test for it, you don't understand the bug well enough to fix it.

For adversarial bugs (prompt injection bypasses, etc.), add the reproduction to the `@adversarial` test suite. For protocol bugs, add an SBE round-trip test. For transaction builder bugs, add a simulation test.

## 9. Branch Naming

Format: `category/description`

| Category | Use |
|----------|-----|
| `feat/` | New feature |
| `fix/` | Bug fix |
| `refactor/` | Code restructuring, no behavior change |
| `docs/` | Documentation only |
| `test/` | Test additions or fixes |
| `chore/` | Build, config, dependencies |

Description is lowercase, hyphen-separated, short.

```
feat/yield-discovery
fix/psbt-fee-estimation
refactor/sbe-codec-buffer-reuse
docs/adr-streaming-protocol
test/adversarial-prompt-injection
chore/upgrade-netty
```

`main` is the default branch. No `develop` branch. Feature branches merge to `main` via PR.

## 10. Protocol Addition

New DeFi protocols can only be added to the protocol index if they meet **all** criteria:

- Audited smart contracts (by a reputable firm)
- Minimum $10M TVL
- Verified source code on block explorers
- No known unresolved exploits
- Active development (commits within 6 months)
- At least 3 months of mainnet operation

**Tooling:**
- Run `aya-index audit --protocol <name> --chain <chain>` to generate an automated due diligence report. Attach it to the ADR.
- The `aya-index` tool fetches ABIs/IDLs and seed data. The developer writes the `ProtocolAdapter` Java class and tests. See [AYA_INDEX_SPEC.md Section 11](AYA_INDEX_SPEC.md) for the exact tool-vs-developer responsibility split.

**Ongoing monitoring:**
- `aya-index health` runs weekly in CI. It checks contract liveness, ABI validity, TVL, exploits, and proxy upgrades. YELLOW/RED warnings require developer triage.

Every new protocol requires an **ADR** documenting the decision. See [AYA_INDEX_SPEC.md](AYA_INDEX_SPEC.md) for the full specification: criteria (Section 9), process (Section 10), tool vs developer roles (Section 11), and the bootstrap set of 24 protocols (Section 8).

---

## Summary

| Rule | One-Liner |
|------|-----------|
| No Docker | Fat JAR only |
| Performance > inheritance | Flat, direct, duplicate if needed |
| Utils > heavy classes | Static methods, no framework magic |
| GC-favorable | Zero-copy, reuse buffers, avoid boxing |
| Specs up to date | Code change = spec change, same PR |
| SnakeYAML config | One format everywhere |
| ADRs | Large changes get a decision record |
| No bugfix without tests | Reproduce → fix → regression test |
| Branch naming | `category/description` (feat/, fix/, refactor/, docs/, test/, chore/) |
| Protocol addition | Audited, $10M+ TVL, verified, no exploits, ADR required |
