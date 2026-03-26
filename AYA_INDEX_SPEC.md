# Aya Index — Technical Specification

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-26
**Parent**: SPEC.md (Aya Backend Specification)

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Commands](#2-commands)
3. [Seed Data Format](#3-seed-data-format)
4. [Refresh Pipeline](#4-refresh-pipeline)
5. [Validate Rules](#5-validate-rules)
6. [Protocol Audit (aya-index audit)](#6-protocol-audit-aya-index-audit)
7. [Protocol Health Monitor (aya-index health)](#7-protocol-health-monitor-aya-index-health)
8. [Bootstrap Protocol Set](#8-bootstrap-protocol-set)
9. [Protocol Addition Criteria](#9-protocol-addition-criteria)
10. [Protocol Addition Process](#10-protocol-addition-process)
11. [Tool vs Developer Responsibilities](#11-tool-vs-developer-responsibilities)
12. [Workflows](#12-workflows)
13. [Module Structure](#13-module-structure)
14. [Configuration](#14-configuration)
15. [Dependencies](#15-dependencies)

---

## 1. Introduction

### 1.1 Purpose

`aya-index` is a **standalone offline CLI tool** — a separate Gradle module producing its own fat JAR — for managing the protocol index seed data used by the Aya backend. It fetches ABIs and IDLs from block explorers and on-chain sources, audits protocols against due diligence criteria, monitors the ongoing health of indexed protocols, and validates the completeness and correctness of the seed data directory.

`aya-index` is distinct from `aya-cli` (the SBE test client for the backend). It never runs at runtime. It runs on a developer machine or in CI to produce static seed files that are committed to the repository.

### 1.2 Scope

**What aya-index does:**

- Fetches contract ABIs from EVM block explorer APIs (Etherscan, Polygonscan, etc.)
- Fetches Solana IDLs from on-chain Anchor PDA accounts and the DeployDAO GitHub index
- Fetches protocol metadata (TVL, APY) from DeFiLlama
- Validates seed data completeness: every protocol has contracts, every contract has an ABI/IDL, every ABI/IDL is valid JSON
- Audits proposed protocols against addition criteria (TVL, audits, exploits, activity, maturity)
- Monitors health of all indexed protocols (contract alive, ABI valid, TVL threshold, exploits, proxy upgrades)
- Writes structured seed files (YAML metadata + JSON ABI/IDL files)

**What aya-index does NOT do:**

- Build transactions (that is `aya-txbuilder` at runtime)
- Communicate with the backend (it is fully offline)
- Run at runtime (it produces static artifacts only)
- Hold or manage private keys
- Interact with the LLM or the agent pipeline
- Serve as the backend test client (that is `aya-cli`)

### 1.3 Relationship to Other Components

| Component | Relationship |
|-----------|-------------|
| **aya-txbuilder** | Consumer. `aya-index` produces seed files that live in `aya-txbuilder/src/main/resources/seed/`. At build time, these files are bundled into the txbuilder JAR. At runtime, the backend loads them into SQLite (see SPEC.md Section 7.5 (Runtime Seed Loading)). |
| **aya-cli** | No relationship. `aya-cli` is the SBE test client for the running backend. `aya-index` is an offline data tool. |
| **aya-backend** | No runtime relationship. `aya-index` never talks to the backend. The backend consumes the seed files produced by `aya-index` indirectly (via the bundled JAR resources). |
| **Block Explorers** | Data source. `aya-index` calls Etherscan/Polygonscan/etc. APIs to fetch ABIs and contract metadata. |
| **DeFiLlama** | Data source. `aya-index` calls DeFiLlama APIs for TVL, APY, and exploit data. |
| **Solana RPC** | Data source. `aya-index` reads on-chain IDL accounts for Anchor programs. |
| **GitHub API** | Data source. `aya-index` checks GitHub activity for protocol repositories and fetches IDLs from DeployDAO. |

---

## 2. Commands

`aya-index` exposes six commands:

### 2.1 `refresh` — Full Refresh

Fetches everything for all bootstrap protocols. This is the primary command for populating or updating the seed data.

```bash
# Full refresh: fetch everything for all bootstrap protocols
aya-index refresh --output aya-txbuilder/src/main/resources/seed/

# Fetch ABIs/IDLs only (skip APY/TVL — those are live at runtime anyway)
aya-index refresh --abis-only --output aya-txbuilder/src/main/resources/seed/
```

See [Section 4: Refresh Pipeline](#4-refresh-pipeline) for the step-by-step process.

### 2.2 `add` — Add a New Protocol

Adds a single protocol (after criteria approval) to the seed data.

```bash
# Add a new protocol to the seed (after criteria approval)
aya-index add --protocol aave-v3 --chain polygon
```

**What `aya-index add` does:**

1. Adds the protocol+chain entry to `protocol_registry.yml`
2. Prompts for contract addresses (or reads from `--contracts` flag)
3. Fetches ABIs/IDLs for those addresses
4. Fetches TVL/APY from DeFiLlama
5. Runs validate

### 2.3 `validate` — Validate Seed Completeness

Checks that the seed data is complete and consistent. See [Section 5: Validate Rules](#5-validate-rules) for the full rule set.

```bash
# Validate the seed (check all protocols have ABIs, contracts, metadata)
aya-index validate --input aya-txbuilder/src/main/resources/seed/
```

### 2.4 `list` — List Indexed Protocols

Shows what is currently in the seed data.

```bash
# Show what's in the seed
aya-index list
```

### 2.5 `audit` — Protocol Due Diligence

Automates the criteria checks from [Section 9: Protocol Addition Criteria](#9-protocol-addition-criteria) for a proposed protocol. Run before adding a new protocol.

```bash
# Automated due diligence for a protocol (before adding)
aya-index audit --protocol compound-v3 --chain ethereum
```

See [Section 6: Protocol Audit](#6-protocol-audit-aya-index-audit) for the full specification.

### 2.6 `health` — Protocol Health Monitor

Health check for all indexed protocols. Run on a CI schedule (weekly) or manually before a release.

```bash
# Health check all indexed protocols (run in CI weekly)
aya-index health --input aya-txbuilder/src/main/resources/seed/
```

See [Section 7: Protocol Health Monitor](#7-protocol-health-monitor-aya-index-health) for the full specification.

---

## 3. Seed Data Format

The bundled seed data lives in the repository and is loaded into SQLite on first backend startup:

```
aya-txbuilder/src/main/resources/seed/
  protocol_registry.yml       # All protocol metadata
  protocol_contracts.yml      # All contract addresses
  abis/                       # Bundled ABI JSON files
    ethereum/
      0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45.json  # Uniswap SwapRouter02
      0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2.json  # Aave V3 Pool
      ...
    polygon/
      ...
    arbitrum/
      ...
  idls/                       # Bundled Solana IDLs
    JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4.json  # Jupiter
    MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD.json  # Marinade
    ...
```

**Files:**

| File | Purpose |
|------|---------|
| `protocol_registry.yml` | Master list of all protocols: ID, name, category, supported chains, TVL snapshot, APY snapshot, `updated_at` timestamp |
| `protocol_contracts.yml` | All contract addresses for each protocol+chain pair |
| `abis/{chain}/{address}.json` | EVM contract ABI JSON files, organized by chain |
| `idls/{programAddress}.json` | Solana IDL JSON files, identified by program address |

---

## 4. Refresh Pipeline

**What `aya-index refresh` does, step by step:**

1. **Load protocol list** — reads `protocol_registry.yml` for the list of bootstrap protocols and their chains.

2. **Fetch contract addresses** — for each protocol+chain, resolve the canonical contract addresses:
   - Known adapters have hardcoded addresses (Uniswap SwapRouter02 on Ethereum = `0x68b346...`)
   - New protocols: look up deployer registries or protocol docs

3. **Fetch ABIs (EVM)** — for each contract address per chain, call the block explorer API:
   - `GET https://api.etherscan.io/api?module=contract&action=getabi&address={address}`
   - Save as `seed/abis/{chain}/{address}.json`
   - **Fail loudly** if any ABI fetch fails (a broken seed should not be committed)

4. **Fetch IDLs (Solana)** — for each program address:
   - Try on-chain IDL account first (Anchor PDA)
   - Fallback to DeployDAO GitHub index
   - Save as `seed/idls/{programAddress}.json`

5. **Fetch metadata** — for each protocol, fetch current snapshot data from DeFiLlama:
   - TVL per chain: `GET https://api.llama.fi/protocol/{protocolSlug}`
   - APY where applicable: `GET https://yields.llama.fi/pools` (filter by protocol)
   - Update `protocol_registry.yml` with latest TVL, APY, and timestamps

6. **Write output** — all files written to the `--output` directory.

7. **Validate** — run `aya-index validate` automatically after refresh to ensure completeness.

---

## 5. Validate Rules

**What `aya-index validate` checks:**

| Rule | Description |
|------|-------------|
| **Registry-to-contracts mapping** | Every protocol in `protocol_registry.yml` has at least one entry in `protocol_contracts.yml` |
| **Contract-to-ABI mapping (EVM)** | Every contract in `protocol_contracts.yml` for an EVM chain has a corresponding ABI file in `seed/abis/{chain}/` |
| **Contract-to-IDL mapping (Solana)** | Every contract in `protocol_contracts.yml` for Solana has a corresponding IDL file in `seed/idls/` |
| **ABI validity** | Every ABI file is valid JSON and contains at least one function signature |
| **IDL validity** | Every IDL file is valid JSON |
| **Bootstrap completeness** | Every bootstrap protocol from [Section 8](#8-bootstrap-protocol-set) is present |
| **Coverage rules** | Every supported chain has at least one DEX + one staking protocol; every category has 2+ protocols |

---

## 6. Protocol Audit (`aya-index audit`)

Automates the criteria checks from [Section 9: Protocol Addition Criteria](#9-protocol-addition-criteria) for a proposed protocol. Run before adding a new protocol.

```bash
aya-index audit --protocol compound-v3 --chain ethereum --chain polygon
```

### 6.1 Checks

| Check | Source | Threshold | Status |
|-------|--------|-----------|--------|
| TVL | DeFiLlama `/protocol/{slug}` | >= $10M | GREEN / RED |
| Contract verified | Block explorer API `getabi` | Verified source | GREEN / RED |
| Audit report exists | Search protocol GitHub, DeFiSafety, Solodit | Found / not found | GREEN / YELLOW |
| GitHub activity | GitHub API (last commit date) | Within 6 months | GREEN / YELLOW / RED |
| Deployment age | Block explorer (contract creation tx timestamp) | >= 3 months | GREEN / RED |
| Known exploits | DeFiLlama `/hacks` endpoint, rekt.news | None unresolved | GREEN / RED |

### 6.2 Output Format

A structured report (YAML and human-readable) with green/yellow/red per criterion:

```
Protocol: Compound V3
Chains: ethereum, polygon

  TVL:              $2.1B          GREEN
  Verified:         Yes (all)      GREEN
  Audit:            OpenZeppelin   GREEN
  GitHub activity:  3 days ago     GREEN
  Deployment age:   18 months      GREEN
  Known exploits:   None           GREEN

  Overall: PASS — all criteria met
```

The developer attaches this report to the ADR. The tool does the legwork; the developer makes the judgment call.

### 6.3 Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| `0` | All criteria GREEN (pass) |
| `1` | Any criterion RED (fail — criteria not met) |
| `2` | Any criterion YELLOW, none RED (needs human review) |

---

## 7. Protocol Health Monitor (`aya-index health`)

A health check for all indexed protocols. Run on a CI schedule (weekly) or manually before a release. Produces warnings — does not break the build.

```bash
aya-index health --input aya-txbuilder/src/main/resources/seed/
```

### 7.1 Checks

| Check | How | Warning Level |
|-------|-----|---------------|
| **Contract alive** | `eth_getCode` returns non-empty (EVM) or account exists (Solana) | RED if dead |
| **ABI still valid** | Call a known function selector on the contract; check it doesn't revert with "unknown function" | YELLOW if mismatch |
| **TVL threshold** | DeFiLlama TVL check | YELLOW if < $5M (potential protocol decline) |
| **Exploit check** | DeFiLlama `/hacks` endpoint — any new entries since `updated_at` in seed? | RED if new exploit found |
| **Contract upgrade** | For upgradeable proxies: check if implementation address changed since last check | YELLOW if upgraded (may need adapter update) |

### 7.2 Output Format

```
Protocol Health Report (2026-03-26)

  uniswap-v3 (ethereum):  All GREEN
  uniswap-v3 (polygon):   All GREEN
  aave-v3 (ethereum):     All GREEN
  aave-v3 (polygon):      YELLOW — proxy implementation changed (0xold → 0xnew)
  lido (ethereum):         All GREEN
  compound-v3 (ethereum):  YELLOW — TVL dropped to $4.8M
  ...

  Summary: 22 GREEN, 2 YELLOW, 0 RED
```

### 7.3 Warning Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **GREEN** | Protocol is healthy | None |
| **YELLOW** | Needs developer attention | Investigate and update adapter if needed |
| **RED** | Action required | Protocol may be dead or compromised. Consider removing from the index. |

### 7.4 CI Integration

Run via `./gradlew protocolHealth` which invokes `aya-index health`. Configure as a weekly CI cron job. Results posted as a CI artifact or Slack notification. Does not fail the build — produces warnings only.

---

## 8. Bootstrap Protocol Set

The following protocols ship on day one. All are pre-approved, have adapters implemented, and their ABIs/IDLs bundled in the seed data.

### 8.1 Bootstrap Coverage Rules

1. Every supported chain must have at least one DEX and one staking/yield protocol
2. Every DeFiLlama category (DEX, lending, staking/liquid staking, bridge, yield/vault) must have at least 2 protocols
3. The top protocol by TVL on each chain must be included
4. Aggregators (1inch, Jupiter, LiFi) are preferred to maximize coverage per adapter

### 8.2 EVM — DEX/Aggregator

| Protocol | Chains | Actions |
|----------|--------|---------|
| Uniswap V3 | Ethereum, Polygon, Arbitrum, Optimism, Base | swap |
| Curve | Ethereum, Polygon, Arbitrum | swap (stablecoins) |
| 1inch | Ethereum, Polygon, Arbitrum, Optimism, Base, BSC, Avalanche | swap (aggregated) |
| PancakeSwap | BSC, Ethereum | swap |
| TraderJoe | Avalanche, Arbitrum | swap |
| SushiSwap | Ethereum, Polygon, Arbitrum | swap |

### 8.3 EVM — Lending

| Protocol | Chains | Actions |
|----------|--------|---------|
| Aave V3 | Ethereum, Polygon, Arbitrum, Optimism, Base, Avalanche | lend, borrow |
| Compound V3 | Ethereum, Polygon, Arbitrum, Base | lend, borrow |

### 8.4 EVM — Staking/Liquid Staking

| Protocol | Chains | Actions |
|----------|--------|---------|
| Lido | Ethereum | stake, unstake |
| Rocket Pool | Ethereum | stake, unstake |
| Ankr | Ethereum, Polygon, BSC, Avalanche | stake, unstake |

### 8.5 EVM — Yield/Vaults

| Protocol | Chains | Actions |
|----------|--------|---------|
| Yearn V3 | Ethereum, Polygon, Arbitrum | deposit, withdraw |
| Beefy | Ethereum, Polygon, Arbitrum, BSC, Avalanche, Optimism, Base | deposit, withdraw |

### 8.6 EVM — Bridge

| Protocol | Chains | Actions |
|----------|--------|---------|
| LI.FI | All EVM chains | bridge |
| Stargate | Ethereum, Polygon, Arbitrum, Optimism, Base, BSC, Avalanche | bridge |

### 8.7 Solana — DEX

| Protocol | Chains | Actions |
|----------|--------|---------|
| Jupiter | Solana | swap |
| Raydium | Solana | swap |
| Orca | Solana | swap |

### 8.8 Solana — Staking/Lending

| Protocol | Chains | Actions |
|----------|--------|---------|
| Marinade | Solana | stake, unstake |
| Jito | Solana | stake, unstake |
| Solend | Solana | lend, borrow |
| Kamino | Solana | lend, borrow, deposit |

### 8.9 Exchange

| Protocol | Chains | Actions |
|----------|--------|---------|
| Aya Trade | Exchange-native | swap, exchange_order |

### 8.10 Totals

**24 protocols**. Every supported chain has DEX + staking coverage. Every DeFiLlama category has 2+ protocols. Bitcoin has no DeFi protocols — only native PSBT send/receive.

---

## 9. Protocol Addition Criteria

New protocols can be added after launch if they meet **all** of the following:

| Criterion | Requirement |
|-----------|-------------|
| **Audit** | Smart contracts audited by a reputable firm (Trail of Bits, OpenZeppelin, Certora, Halborn, etc.) |
| **TVL** | Minimum $10M TVL across supported chains |
| **Verified source** | Source code verified on all relevant block explorers |
| **No exploits** | No known unresolved exploits or critical vulnerabilities |
| **Active** | Commits within the last 6 months |
| **Maturity** | At least 3 months of mainnet operation |

**Exception**: Aya Trade is exempt from external audit and TVL criteria (it is the team's own exchange).

---

## 10. Protocol Addition Process

1. **Automated audit**: Run `aya-index audit --protocol <name> --chain <chain>` to generate a due diligence report (see [Section 6](#6-protocol-audit-aya-index-audit)). Attach the report to the issue.
2. Open an issue proposing the protocol with the audit report and evidence that all criteria in [Section 9](#9-protocol-addition-criteria) are met.
3. Write an ADR documenting: why this protocol, what it adds, risk assessment, which chains.
4. Run `aya-index add --protocol <id> --chain <chain>` to fetch ABIs/IDLs and populate seed data.
5. **Developer writes** the `ProtocolAdapter` Java class — this is the protocol-specific transaction building logic that cannot be auto-generated.
6. **Developer writes** tests: unit (parameter resolution, calldata encoding) + integration (testnet simulation).
7. Run `aya-index validate` to confirm seed completeness.
8. PR review by at least one team member.

---

## 11. Tool vs Developer Responsibilities

| Concern | Responsibility | Output |
|---------|---------------|--------|
| Fetch contract ABIs/IDLs | `aya-index` (automated) | Seed data files: YAML metadata + JSON ABI/IDL files |
| Fetch protocol metadata (TVL, APY) | `aya-index` (automated) | `protocol_registry.yml` entries |
| Automated due diligence check | `aya-index audit` (automated) | Audit report (green/yellow/red per criterion) |
| Ongoing protocol health monitoring | `aya-index health` (automated, CI cron) | Health report with warnings |
| Decide whether to add a protocol | Developer (manual) | ADR with judgment call |
| Build transactions for the protocol | Developer (manual) | Java `ProtocolAdapter` class |
| Write tests | Developer (manual) | Unit + integration tests |
| SBE schema changes (if needed) | Developer (manual) | Schema XML + regenerated codecs |

`aya-index` handles the **data fetching and verification**. The developer handles the **judgment and implementation**.

---

## 12. Workflows

### 12.1 Initial Bootstrap

First time: populate seed from scratch for all 24 bootstrap protocols.

```bash
# 1. First time: populate seed from scratch for all 24 bootstrap protocols
aya-index refresh --output aya-txbuilder/src/main/resources/seed/

# 2. Validate
aya-index validate --input aya-txbuilder/src/main/resources/seed/

# 3. Commit
git add aya-txbuilder/src/main/resources/seed/
git commit -m "feat/bootstrap-protocol-index: seed data for 24 protocols"
```

### 12.2 Adding a New Protocol After Launch

```bash
# 1. Add to the registry
aya-index add --protocol compound-v3 --chain ethereum --chain polygon

# 2. Verify
aya-index validate --input aya-txbuilder/src/main/resources/seed/

# 3. Commit with ADR
git add aya-txbuilder/src/main/resources/seed/ docs/adr/
git commit -m "feat/add-compound-v3: add Compound V3 to protocol index"
```

### 12.3 Pre-Release Refresh (CI or Manual)

Weekly or before each release: update ABIs (in case contracts were upgraded) and metadata.

```bash
# Weekly or before each release: update ABIs and metadata
aya-index refresh --output aya-txbuilder/src/main/resources/seed/
git diff aya-txbuilder/src/main/resources/seed/  # review changes
git add -p && git commit -m "chore/refresh-protocol-index"
```

---

## 13. Module Structure

```
aya-index/
  src/main/java/aya/index/
    AyaIndex.java              # Entry point, picocli
    RefreshCommand.java
    AddCommand.java
    ValidateCommand.java
    ListCommand.java
    AuditCommand.java
    HealthCommand.java
    fetcher/
      AbiFetcher.java
      IdlFetcher.java
      DefiLlamaFetcher.java
      ExploitChecker.java
      GitHubActivityChecker.java
    writer/
      SeedWriter.java
      AbiWriter.java
      IdlWriter.java
    report/
      AuditReport.java
      HealthReport.java
```

### 13.1 Package Descriptions

| Package | Purpose |
|---------|---------|
| `aya.index` | Top-level: entry point (`AyaIndex.java` with picocli `@Command`) and all command classes |
| `aya.index.fetcher` | Data fetching: block explorer ABI calls, on-chain IDL reads, DeFiLlama API calls, exploit database checks, GitHub activity checks |
| `aya.index.writer` | File writing: YAML seed metadata, ABI JSON files, IDL JSON files |
| `aya.index.report` | Report generation: structured audit reports and health reports (YAML + human-readable) |

---

## 14. Configuration

`aya-index` reads configuration from a YAML file (`~/.aya-index/config.yml` or `--config` flag):

```yaml
# Block explorer API keys (required for ABI fetching)
block-explorers:
  etherscan:
    api-key: "${ETHERSCAN_API_KEY}"
    base-url: "https://api.etherscan.io/api"
  polygonscan:
    api-key: "${POLYGONSCAN_API_KEY}"
    base-url: "https://api.polygonscan.com/api"
  arbiscan:
    api-key: "${ARBISCAN_API_KEY}"
    base-url: "https://api.arbiscan.io/api"
  optimistic-etherscan:
    api-key: "${OPTIMISTIC_ETHERSCAN_API_KEY}"
    base-url: "https://api-optimistic.etherscan.io/api"
  basescan:
    api-key: "${BASESCAN_API_KEY}"
    base-url: "https://api.basescan.org/api"
  bscscan:
    api-key: "${BSCSCAN_API_KEY}"
    base-url: "https://api.bscscan.com/api"
  snowscan:
    api-key: "${SNOWSCAN_API_KEY}"
    base-url: "https://api.snowscan.xyz/api"

# GitHub API (required for activity checks and DeployDAO IDL fallback)
github:
  token: "${GITHUB_TOKEN}"

# Solana RPC (required for on-chain IDL fetching)
solana:
  rpc-url: "https://api.mainnet-beta.solana.com"

# DeFiLlama (no API key required)
defillama:
  base-url: "https://api.llama.fi"
  yields-url: "https://yields.llama.fi"

# Timeouts
timeouts:
  connect-ms: 5000
  read-ms: 30000
```

Environment variables can be used via `${VAR_NAME}` syntax. API keys should be stored as environment variables, not committed to the repository.

---

## 15. Dependencies

| Dependency | Purpose |
|-----------|---------|
| **picocli** | CLI framework: command parsing, `@Command` annotations, help text generation |
| **SnakeYAML** | YAML reading and writing for `protocol_registry.yml`, `protocol_contracts.yml`, config, and report output |
| **java.net.http** (built-in) | HTTP client for block explorer APIs, DeFiLlama, GitHub API, Solana RPC. No external HTTP library needed. |
| **Bouncy Castle** | Cryptographic library used for Solana IDL account address derivation (Anchor PDA calculation) |

**No dependency on `aya-protocol`, `aya-backend`, or `aya-txbuilder`**. `aya-index` is a fully standalone module. It produces files that are consumed by `aya-txbuilder`, but has no compile-time or runtime dependency on it.

---

## Cross-References

| Topic | Location |
|-------|----------|
| Runtime seed loading (how the backend consumes seed files) | SPEC.md Section 7.5 (Runtime Seed Loading) |
| Protocol Adapter interface (what the developer writes) | SPEC.md Section 7.7.1 |
| Protocol Adapter registry and transaction pipeline | SPEC.md Section 7.8 |
| Bootstrap protocol set (original source) | SPEC.md Section 7.7.5 |
| Protocol addition criteria (original source) | SPEC.md Section 7.7.5 |
