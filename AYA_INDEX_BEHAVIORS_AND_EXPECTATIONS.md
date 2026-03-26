# Aya Index — Behaviors and Expectations

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-26
**Parent**: AYA_INDEX_SPEC.md

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Desired Behaviors](#2-desired-behaviors)
3. [Undesired Behaviors](#3-undesired-behaviors)
4. [Edge Cases](#4-edge-cases)
5. [Exit Codes](#5-exit-codes)

---

## 1. Introduction

This document defines the expected behavioral contract for all `aya-index` commands. It serves as a reference for implementers, reviewers, and test authors. Each command has explicit desired behaviors, undesired behaviors (anti-patterns to guard against), edge cases with expected handling, and exit codes.

The guiding principle: `aya-index` is a **data integrity tool**. It must be loud about failures, strict about completeness, and transparent about what it found. A developer who runs `aya-index` should never be surprised by what ended up in the seed — or what was silently omitted.

---

## 2. Desired Behaviors

### 2.1 `refresh`

| Behavior | Description |
|----------|-------------|
| **Fetches all data** | For every protocol in `protocol_registry.yml`, fetches ABIs (EVM), IDLs (Solana), and metadata (TVL, APY) from external sources. No protocol is skipped. |
| **Fails loudly on any ABI fetch failure** | If any block explorer API call fails (HTTP error, empty response, invalid JSON), the entire refresh aborts with a non-zero exit code and a clear error message identifying which contract on which chain failed. A broken seed must never be committed. |
| **Fails loudly on any IDL fetch failure** | If an IDL cannot be found on-chain or via DeployDAO fallback, the refresh aborts. Missing IDLs are not acceptable. |
| **Runs validate automatically** | After writing all files, `refresh` invokes `validate` internally. If validation fails, the refresh exits with a non-zero code even though the files were written. The developer sees both the fetch results and the validation errors. |
| **Overwrites existing files** | Running refresh on an existing seed directory updates all files. It does not preserve stale data. |
| **Reports progress** | Prints progress to stdout as it fetches: which protocol, which chain, which contract. Long-running operations (many ABIs) should show incremental output, not silence for minutes. |
| **Respects `--abis-only`** | When the flag is set, skips TVL/APY metadata fetching. Only fetches ABIs and IDLs. Does not modify `protocol_registry.yml` metadata fields (TVL, APY, timestamps). |

### 2.2 `add`

| Behavior | Description |
|----------|-------------|
| **Adds one protocol** | Adds a single protocol to the registry for the specified chain(s). Does not modify other protocols. |
| **Fetches data for the new protocol** | Fetches ABIs/IDLs and metadata for the newly added protocol only. Does not re-fetch data for existing protocols. |
| **Prompts for contract addresses** | If `--contracts` flag is not provided, interactively prompts the developer for contract addresses. If `--contracts` is provided, uses those addresses directly. |
| **Validates after add** | Runs the full validate suite after adding, to confirm the new protocol integrates correctly with the existing seed. |
| **Idempotent for existing entries** | If the protocol+chain already exists in the registry, updates the existing entry rather than creating a duplicate. Prints a warning that it is updating, not adding. |

### 2.3 `validate`

| Behavior | Description |
|----------|-------------|
| **Checks completeness** | Verifies every rule defined in AYA_INDEX_SPEC.md Section 5 (Validate Rules). |
| **Clear error messages per failure** | Each validation failure produces a specific, actionable error message. Examples: `"Protocol 'aave-v3' has no entry in protocol_contracts.yml"`, `"Missing ABI: ethereum/0x1234...5678.json"`, `"ABI ethereum/0xabcd...ef01.json is not valid JSON"`. |
| **Reports all failures, not just the first** | Validate runs all rules and reports every failure found, not just the first one. The developer sees the full picture in a single run. |
| **Distinguishes errors from warnings** | Missing ABIs and broken JSON are errors (non-zero exit). Missing optional metadata fields (e.g., APY for a staking protocol that does not have pools) are warnings (logged but do not cause failure). |
| **Zero exit on success** | If all rules pass, exits with code 0 and prints a success summary (e.g., "Validated 24 protocols, 87 contracts, 87 ABIs/IDLs. All checks passed."). |

### 2.4 `audit`

| Behavior | Description |
|----------|-------------|
| **Green/yellow/red per criterion** | Each of the six criteria (TVL, verified source, audit report, GitHub activity, deployment age, known exploits) is independently evaluated and assigned a color. |
| **Structured output** | Produces both YAML (machine-readable) and human-readable text output. The YAML output can be consumed by CI or attached to issues. |
| **Correct exit codes** | Exit 0 if all green. Exit 1 if any red. Exit 2 if any yellow but no red. See [Section 5](#5-exit-codes). |
| **Fetches live data** | Every check hits the live API. No caching. The audit result reflects the current state of the protocol, not a stale snapshot. |
| **Multi-chain support** | When `--chain` is specified multiple times, checks are run per chain (e.g., contract verification is checked on each chain separately). TVL is the aggregate across all specified chains. |
| **Does not modify the seed** | The audit command is read-only with respect to the seed directory. It only produces a report. |

### 2.5 `health`

| Behavior | Description |
|----------|-------------|
| **Per-protocol status** | Each protocol+chain combination gets its own status line with individual check results. |
| **Summary line** | After all protocols, prints a summary: `"Summary: X GREEN, Y YELLOW, Z RED"`. |
| **Warnings only, never breaks the build** | The health command always exits with code 0, regardless of findings. YELLOW and RED are reported as warnings. This is by design: health issues require human judgment, not automated build failure. |
| **Checks all indexed protocols** | Every protocol+chain in the seed is checked. None are skipped. |
| **Timestamps** | The report header includes the date. Each protocol entry can include the `updated_at` timestamp from the seed for context. |

### 2.6 `list`

| Behavior | Description |
|----------|-------------|
| **Shows all protocols** | Lists every protocol in `protocol_registry.yml` with its ID, name, category, supported chains, and action types. |
| **Chain coverage summary** | Shows a per-chain summary: which protocols cover each chain, and whether the coverage rules (DEX + staking per chain, 2+ per category) are met. |
| **Human-readable table** | Output is a formatted table suitable for terminal display. |

---

## 3. Undesired Behaviors

These are anti-patterns that the implementation must guard against. Tests should verify their absence.

### 3.1 Silent Failures

**MUST NOT** swallow fetch errors. If a block explorer API returns an error, a timeout, or an empty body, the tool must report the failure and exit with a non-zero code (for `refresh` and `add`). Logging an error and continuing is not acceptable — the seed would be incomplete.

**Example of the wrong behavior:**
```
Fetching ABI for ethereum/0x1234...5678... ERROR (timeout)
Fetching ABI for ethereum/0xabcd...ef01... OK
...
Refresh complete. (exit 0)
```

**Correct behavior:**
```
Fetching ABI for ethereum/0x1234...5678... FAILED (timeout after 30s)
ERROR: ABI fetch failed for 1 contract(s). Seed is incomplete. Aborting.
(exit 1)
```

### 3.2 Partial Seed

**MUST NOT** produce a seed directory where some ABIs are present and others are missing without an error. A partial seed means the backend will fail at runtime when it tries to build a transaction for a protocol whose ABI was silently skipped. The `refresh` command must be all-or-nothing for the ABI/IDL fetch phase.

### 3.3 Stale Audit Data

**MUST NOT** use cached data for the `audit` command. Every audit invocation must hit live APIs. Caching audit results would defeat the purpose — the audit is meant to reflect the protocol's current state (current TVL, current exploit status, current GitHub activity).

### 3.4 Health Check Breaking the Build

**MUST NOT** return a non-zero exit code from the `health` command based on protocol status. Health findings (YELLOW, RED) are informational. They require human investigation. Automatically failing the CI build on a health finding would create false urgency and alert fatigue. The health command always exits 0.

### 3.5 Modifying Seed During Audit or Health

**MUST NOT** write to the seed directory during `audit` or `health` commands. These commands are read-only with respect to the seed directory. The `audit` command does not even read the seed — it only queries external APIs. The `health` command reads the seed to know which protocols to check but does not modify it. Only `refresh` and `add` write to the seed.

### 3.6 Duplicate Registry Entries

**MUST NOT** create duplicate entries in `protocol_registry.yml` or `protocol_contracts.yml` when running `add` for a protocol+chain that already exists. Must detect the existing entry and update it (with a warning that it is updating rather than adding).

---

## 4. Edge Cases

### 4.1 Block Explorer API Rate Limited During Refresh

**Scenario**: Etherscan returns HTTP 429 (rate limit exceeded) while fetching ABIs for the 15th contract.

**Expected behavior**:
- Implement exponential backoff with a maximum of 3 retries per request.
- If still rate-limited after retries, abort the refresh with a clear error: `"Rate limited by etherscan.io after 3 retries. Fetched 14/87 ABIs. Consider adding API key to config or retrying later."`
- Exit with non-zero code.
- Do not produce a partial seed without an error.

### 4.2 Protocol Not Found on DeFiLlama

**Scenario**: `aya-index audit --protocol some-new-protocol` but DeFiLlama does not have a matching slug.

**Expected behavior**:
- The TVL check returns RED with message: `"Protocol 'some-new-protocol' not found on DeFiLlama. TVL cannot be verified."`
- Other checks (contract verified, GitHub activity, etc.) proceed independently.
- The overall audit result reflects the RED from TVL.
- For `refresh`: if a bootstrap protocol is not found on DeFiLlama, the metadata fetch for that protocol is marked as a warning (TVL/APY set to null in the YAML with a comment), but ABI/IDL fetching continues. The validate step will not fail on missing DeFiLlama metadata since it is supplementary.

### 4.3 Solana IDL Not Found On-Chain or on DeployDAO

**Scenario**: A Solana program address is in the registry, but the IDL account does not exist on-chain (not an Anchor program or IDL was closed), and DeployDAO does not have it either.

**Expected behavior**:
- `refresh`: Aborts with error: `"IDL not found for program JUP6Lk... — tried on-chain Anchor PDA and DeployDAO index. Cannot proceed."`
- `add`: Same behavior — aborts with error.
- `audit`: Not applicable (audit does not fetch IDLs).
- `health`: Reports RED for that program: `"IDL account not found on-chain. Program may have been closed or migrated."`

### 4.4 Empty Seed Directory (First Run)

**Scenario**: Running `aya-index refresh --output seed/` where the `seed/` directory is empty or does not exist.

**Expected behavior**:
- Creates the directory structure: `seed/abis/{chain}/`, `seed/idls/`.
- Creates `protocol_registry.yml` and `protocol_contracts.yml` from scratch using the hardcoded bootstrap protocol list.
- Fetches all ABIs, IDLs, and metadata.
- Runs validate (which should pass if all fetches succeeded).
- This is the expected first-run flow.

### 4.5 Validate on Empty Seed

**Scenario**: Running `aya-index validate --input seed/` where the seed directory is empty.

**Expected behavior**:
- Reports errors for every missing component: missing `protocol_registry.yml`, missing `protocol_contracts.yml`, no ABI files, no IDL files, no bootstrap protocols present.
- Does not crash or throw an unhandled exception.
- Exits with non-zero code.

### 4.6 Network Timeout During Health Check

**Scenario**: DeFiLlama is down during a weekly health check CI run.

**Expected behavior**:
- Checks that depend on DeFiLlama (TVL threshold, exploit check) report YELLOW with message: `"DeFiLlama unreachable (timeout). TVL and exploit data unavailable."`
- Checks that do not depend on DeFiLlama (contract alive, ABI valid, proxy upgrade) proceed normally.
- Health check still exits 0 (it never breaks the build).
- The summary reflects the incomplete data: `"Summary: 18 GREEN, 6 YELLOW (4 due to DeFiLlama timeout), 0 RED"`.

### 4.7 Contract Upgraded (Proxy Implementation Changed)

**Scenario**: Aave V3 on Polygon upgraded its proxy implementation between health checks.

**Expected behavior**:
- Health check reports YELLOW: `"aave-v3 (polygon): YELLOW — proxy implementation changed (0xOldImpl -> 0xNewImpl)"`.
- Developer investigates: does the new implementation still match the existing ABI? If yes, no action needed. If the ABI changed, re-run refresh and update the adapter.
- Health check does NOT automatically update the seed or fetch the new ABI. That is the developer's job after investigation.

### 4.8 Block Explorer Returns Invalid JSON

**Scenario**: A block explorer API returns a 200 OK but with malformed JSON in the ABI field.

**Expected behavior**:
- `refresh`: Treats this as a fetch failure. Reports: `"ABI for ethereum/0x1234...5678 is not valid JSON (parse error at position 4521). Aborting refresh."`
- Does not write the invalid JSON to the seed directory.
- Exits with non-zero code.

### 4.9 Audit for Aya Trade

**Scenario**: Developer runs `aya-index audit --protocol aya-trade`.

**Expected behavior**:
- Recognizes Aya Trade as the team's own exchange (exempt from external audit and TVL criteria per AYA_INDEX_SPEC.md Section 9).
- Reports: `"Aya Trade is exempt from external audit and TVL criteria (team-owned exchange). Skipping TVL and audit report checks."`
- Remaining checks (verified source, activity, deployment age, exploits) are still run if applicable.
- Exit code reflects only the non-exempt checks.

### 4.10 Multiple Chains Fail During Refresh

**Scenario**: 3 out of 7 EVM block explorer APIs are down simultaneously.

**Expected behavior**:
- The refresh fails and reports all 3 failures, not just the first. Each failure includes the chain name, contract address, and the specific error (timeout, HTTP 500, etc.).
- The seed is NOT partially written — the fetch phase collects all results before writing. If any fetch failed, no files are written.
- Exit with non-zero code.
- Example output:
  ```
  FAILED: ethereum/0x1234...5678 — Connection refused (etherscan.io)
  FAILED: polygon/0xabcd...ef01 — HTTP 500 (polygonscan.com)
  FAILED: arbitrum/0x5678...9abc — Timeout after 30s (arbiscan.io)
  ERROR: 3 ABI fetch(es) failed across 3 chains. Seed not written. Fix network issues and retry.
  (exit 1)
  ```

---

## 5. Exit Codes

### 5.1 Per-Command Exit Codes

#### `refresh`

| Exit Code | Meaning |
|-----------|---------|
| `0` | All ABIs/IDLs fetched successfully, metadata updated, validation passed |
| `1` | One or more ABI/IDL fetch failures, or validation failed after fetch |

#### `add`

| Exit Code | Meaning |
|-----------|---------|
| `0` | Protocol added, data fetched, validation passed |
| `1` | Fetch failure for the new protocol, or validation failed after add |

#### `validate`

| Exit Code | Meaning |
|-----------|---------|
| `0` | All validation rules passed |
| `1` | One or more validation rules failed |

#### `audit`

| Exit Code | Meaning |
|-----------|---------|
| `0` | All criteria GREEN (protocol meets all addition requirements) |
| `1` | Any criterion RED (protocol does not meet requirements) |
| `2` | Any criterion YELLOW, no RED (needs human review — e.g., audit report not found but everything else is green) |

#### `health`

| Exit Code | Meaning |
|-----------|---------|
| `0` | Always. Health check never fails the build. Findings are reported as warnings in the output. |

#### `list`

| Exit Code | Meaning |
|-----------|---------|
| `0` | List printed successfully |
| `1` | Seed directory not found or `protocol_registry.yml` is missing/unparseable |

### 5.2 General Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| `127` | Unknown command or invalid arguments (picocli usage error) |
| `126` | Configuration error (missing config file, missing required API keys) |

### 5.3 Summary Table

| Command | Code 0 | Code 1 | Code 2 |
|---------|--------|--------|--------|
| `refresh` | All data fetched and validated | Any fetch or validation failure | -- |
| `add` | Protocol added and validated | Fetch or validation failure | -- |
| `validate` | Seed is complete and correct | Validation failures found | -- |
| `list` | Listed successfully | Seed directory missing or unreadable | -- |
| `audit` | All criteria GREEN | Any criterion RED | Any criterion YELLOW (no RED) |
| `health` | Always 0 (warnings only) | -- | -- |

---

*For the full specification, see [AYA_INDEX_SPEC.md](AYA_INDEX_SPEC.md).*
*For the architecture, see [AYA_INDEX_ARCHITECTURE.md](AYA_INDEX_ARCHITECTURE.md).*
