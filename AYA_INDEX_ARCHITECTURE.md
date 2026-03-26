# Aya Index — Architecture Document

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-26
**Parent**: AYA_INDEX_SPEC.md

---

## Table of Contents

1. [System Context](#1-system-context)
2. [Component Diagram](#2-component-diagram)
3. [Data Flow — Refresh](#3-data-flow--refresh)
4. [Data Flow — Audit](#4-data-flow--audit)
5. [Data Flow — Health Check](#5-data-flow--health-check)
6. [Deployment](#6-deployment)

---

## 1. System Context

`aya-index` is an offline CLI tool that interacts with external data sources to produce seed files. Those seed files are committed to the repository and consumed by `aya-txbuilder` at build time.

```mermaid
C4Context
    title System Context — aya-index

    Person(dev, "Developer", "Runs aya-index on their machine or CI runs it on schedule")

    System(ayaIndex, "aya-index", "Offline CLI tool for managing protocol index seed data")

    System_Ext(etherscan, "Block Explorers", "Etherscan, Polygonscan, Arbiscan, etc. — ABI fetching, contract verification, deployment age")
    System_Ext(defillama, "DeFiLlama", "TVL, APY, exploit/hack data")
    System_Ext(github, "GitHub", "Protocol activity checks, DeployDAO IDL index")
    System_Ext(solanaRpc, "Solana RPC", "On-chain IDL account reads (Anchor PDA)")

    System(repo, "Git Repository", "Stores seed files in aya-txbuilder/src/main/resources/seed/")
    System(txbuilder, "aya-txbuilder", "Consumes seed files at build time, bundles into JAR")

    Rel(dev, ayaIndex, "Runs commands", "CLI")
    Rel(ayaIndex, etherscan, "Fetches ABIs, contract metadata", "HTTPS")
    Rel(ayaIndex, defillama, "Fetches TVL, APY, exploits", "HTTPS")
    Rel(ayaIndex, github, "Checks activity, fetches IDLs", "HTTPS")
    Rel(ayaIndex, solanaRpc, "Reads IDL accounts", "JSON-RPC")
    Rel(ayaIndex, repo, "Writes seed files", "filesystem")
    Rel(repo, txbuilder, "Seed files bundled at build time", "classpath resources")
```

**Key boundaries:**

- `aya-index` never communicates with `aya-backend` or `aya-txbuilder` at runtime.
- The only output of `aya-index` is files written to the filesystem.
- The only inputs are the existing seed directory (for validate/health) and external APIs (for refresh/add/audit).

---

## 2. Component Diagram

```mermaid
graph TB
    subgraph "aya-index"
        EP[AyaIndex.java<br/>Entry Point + picocli]

        EP --> RC[RefreshCommand]
        EP --> AC[AddCommand]
        EP --> VC[ValidateCommand]
        EP --> LC[ListCommand]
        EP --> AUC[AuditCommand]
        EP --> HC[HealthCommand]

        subgraph "fetcher/"
            AF[AbiFetcher<br/>Block explorer APIs]
            IF[IdlFetcher<br/>Solana RPC + DeployDAO]
            DLF[DefiLlamaFetcher<br/>TVL, APY, pools]
            EC[ExploitChecker<br/>DeFiLlama /hacks]
            GAC[GitHubActivityChecker<br/>GitHub API]
        end

        subgraph "writer/"
            SW[SeedWriter<br/>protocol_registry.yml<br/>protocol_contracts.yml]
            AW[AbiWriter<br/>abis/{chain}/{address}.json]
            IW[IdlWriter<br/>idls/{programAddress}.json]
        end

        subgraph "report/"
            AR[AuditReport<br/>YAML + human-readable]
            HR[HealthReport<br/>YAML + human-readable]
        end

        RC --> AF
        RC --> IF
        RC --> DLF
        RC --> SW
        RC --> AW
        RC --> IW
        RC --> VC

        AC --> AF
        AC --> IF
        AC --> DLF
        AC --> SW
        AC --> AW
        AC --> IW
        AC --> VC

        AUC --> DLF
        AUC --> AF
        AUC --> GAC
        AUC --> EC
        AUC --> AR

        HC --> AF
        HC --> DLF
        HC --> EC
        HC --> HR
    end

    subgraph "External APIs"
        BE[Block Explorers<br/>Etherscan, Polygonscan, etc.]
        DL[DeFiLlama<br/>api.llama.fi / yields.llama.fi]
        GH[GitHub API<br/>api.github.com]
        SR[Solana RPC<br/>api.mainnet-beta.solana.com]
    end

    subgraph "Output"
        SEED[seed/<br/>YAML + JSON files]
    end

    AF --> BE
    IF --> SR
    IF --> GH
    DLF --> DL
    EC --> DL
    GAC --> GH

    SW --> SEED
    AW --> SEED
    IW --> SEED
```

**Component responsibilities:**

| Component | Responsibility |
|-----------|---------------|
| `AyaIndex` | Entry point. Parses CLI arguments via picocli, routes to the correct command. |
| `RefreshCommand` | Orchestrates a full refresh: load protocol list, invoke fetchers, invoke writers, run validate. |
| `AddCommand` | Adds a single protocol: update registry, invoke fetchers for that protocol, run validate. |
| `ValidateCommand` | Reads the seed directory and checks all completeness rules. |
| `ListCommand` | Reads `protocol_registry.yml` and prints a formatted table. |
| `AuditCommand` | Runs due diligence checks against external APIs and produces an audit report. |
| `HealthCommand` | Runs health checks for all indexed protocols and produces a health report. |
| `AbiFetcher` | Calls block explorer APIs to fetch EVM contract ABIs. |
| `IdlFetcher` | Reads Solana on-chain IDL accounts (Anchor PDA) with fallback to DeployDAO GitHub. |
| `DefiLlamaFetcher` | Calls DeFiLlama for TVL, APY, and pool data. |
| `ExploitChecker` | Calls DeFiLlama `/hacks` endpoint to check for known exploits. |
| `GitHubActivityChecker` | Calls GitHub API to check last commit date for protocol repositories. |
| `SeedWriter` | Writes `protocol_registry.yml` and `protocol_contracts.yml`. |
| `AbiWriter` | Writes ABI JSON files to `seed/abis/{chain}/{address}.json`. |
| `IdlWriter` | Writes IDL JSON files to `seed/idls/{programAddress}.json`. |
| `AuditReport` | Generates structured audit output (YAML + human-readable text). |
| `HealthReport` | Generates structured health output (YAML + human-readable text). |

---

## 3. Data Flow — Refresh

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant CLI as AyaIndex (picocli)
    participant RC as RefreshCommand
    participant AF as AbiFetcher
    participant IF as IdlFetcher
    participant DLF as DefiLlamaFetcher
    participant SW as SeedWriter
    participant AW as AbiWriter
    participant IW as IdlWriter
    participant VC as ValidateCommand
    participant BE as Block Explorers
    participant SR as Solana RPC
    participant GH as GitHub (DeployDAO)
    participant DL as DeFiLlama

    Dev->>CLI: aya-index refresh --output seed/
    CLI->>RC: execute()

    Note over RC: Step 1: Load protocol list
    RC->>RC: Parse protocol_registry.yml

    Note over RC: Step 2: Fetch contract addresses
    RC->>RC: Resolve canonical addresses per protocol+chain

    Note over RC: Step 3: Fetch ABIs (EVM)
    loop For each EVM contract
        RC->>AF: fetchAbi(chain, address)
        AF->>BE: GET /api?module=contract&action=getabi&address={addr}
        BE-->>AF: ABI JSON
        AF-->>RC: ABI data
        RC->>AW: write(chain, address, abiJson)
        AW->>AW: Save to seed/abis/{chain}/{address}.json
    end

    Note over RC: Step 4: Fetch IDLs (Solana)
    loop For each Solana program
        RC->>IF: fetchIdl(programAddress)
        IF->>SR: Read IDL account (Anchor PDA)
        alt IDL found on-chain
            SR-->>IF: IDL data
        else IDL not on-chain
            IF->>GH: Fetch from DeployDAO index
            GH-->>IF: IDL data
        end
        IF-->>RC: IDL data
        RC->>IW: write(programAddress, idlJson)
        IW->>IW: Save to seed/idls/{programAddress}.json
    end

    Note over RC: Step 5: Fetch metadata
    loop For each protocol
        RC->>DLF: fetchTvl(protocolSlug)
        DLF->>DL: GET /protocol/{slug}
        DL-->>DLF: TVL data
        RC->>DLF: fetchApy(protocolSlug)
        DLF->>DL: GET /pools (filtered)
        DL-->>DLF: APY data
    end

    Note over RC: Step 6: Write output
    RC->>SW: writeRegistry(protocols)
    SW->>SW: Save protocol_registry.yml
    RC->>SW: writeContracts(contracts)
    SW->>SW: Save protocol_contracts.yml

    Note over RC: Step 7: Validate
    RC->>VC: validate(seedDir)
    VC->>VC: Check all rules
    VC-->>RC: Validation result

    RC-->>CLI: Exit code (0 = success)
    CLI-->>Dev: Output summary
```

---

## 4. Data Flow — Audit

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant CLI as AyaIndex (picocli)
    participant AUC as AuditCommand
    participant DLF as DefiLlamaFetcher
    participant AF as AbiFetcher
    participant EC as ExploitChecker
    participant GAC as GitHubActivityChecker
    participant AR as AuditReport
    participant BE as Block Explorers
    participant DL as DeFiLlama
    participant GH as GitHub API

    Dev->>CLI: aya-index audit --protocol compound-v3 --chain ethereum
    CLI->>AUC: execute()

    Note over AUC: Check 1: TVL
    AUC->>DLF: fetchTvl("compound-v3")
    DLF->>DL: GET /protocol/compound-v3
    DL-->>DLF: TVL data ($2.1B)
    DLF-->>AUC: TVL >= $10M? GREEN

    Note over AUC: Check 2: Contract verified
    AUC->>AF: checkVerified(chain, address)
    AF->>BE: GET /api?module=contract&action=getabi&address={addr}
    BE-->>AF: ABI (verified source)
    AF-->>AUC: Verified? GREEN

    Note over AUC: Check 3: Audit report exists
    AUC->>GAC: searchAuditReports("compound-v3")
    GAC->>GH: Search protocol repo, DeFiSafety, Solodit
    GH-->>GAC: Audit found (OpenZeppelin)
    GAC-->>AUC: Audit exists? GREEN

    Note over AUC: Check 4: GitHub activity
    AUC->>GAC: checkLastCommit("compound-v3")
    GAC->>GH: GET /repos/{owner}/{repo}/commits?per_page=1
    GH-->>GAC: Last commit: 3 days ago
    GAC-->>AUC: Within 6 months? GREEN

    Note over AUC: Check 5: Deployment age
    AUC->>AF: checkDeploymentAge(chain, address)
    AF->>BE: Get contract creation tx timestamp
    BE-->>AF: Created 18 months ago
    AF-->>AUC: >= 3 months? GREEN

    Note over AUC: Check 6: Known exploits
    AUC->>EC: checkExploits("compound-v3")
    EC->>DL: GET /hacks (filter by protocol)
    DL-->>EC: No unresolved exploits
    EC-->>AUC: None unresolved? GREEN

    Note over AUC: Generate report
    AUC->>AR: generate(results)
    AR->>AR: Format YAML + human-readable
    AR-->>AUC: Formatted report

    AUC-->>CLI: Exit code (0=all green, 1=any red, 2=any yellow)
    CLI-->>Dev: Print report
```

---

## 5. Data Flow — Health Check

```mermaid
sequenceDiagram
    participant Dev as Developer / CI
    participant CLI as AyaIndex (picocli)
    participant HC as HealthCommand
    participant AF as AbiFetcher
    participant DLF as DefiLlamaFetcher
    participant EC as ExploitChecker
    participant HR as HealthReport
    participant BE as Block Explorers
    participant DL as DeFiLlama
    participant RPC as Chain RPCs

    Dev->>CLI: aya-index health --input seed/
    CLI->>HC: execute()

    HC->>HC: Load protocol_registry.yml + protocol_contracts.yml

    loop For each protocol+chain
        Note over HC: Check 1: Contract alive
        HC->>AF: checkContractAlive(chain, address)
        AF->>RPC: eth_getCode(address) [EVM] / getAccountInfo [Solana]
        RPC-->>AF: Code exists (non-empty)
        AF-->>HC: GREEN / RED

        Note over HC: Check 2: ABI still valid
        HC->>AF: checkAbiValid(chain, address, knownSelector)
        AF->>RPC: eth_call with known function selector
        RPC-->>AF: No "unknown function" revert
        AF-->>HC: GREEN / YELLOW

        Note over HC: Check 3: TVL threshold
        HC->>DLF: fetchTvl(protocolSlug)
        DLF->>DL: GET /protocol/{slug}
        DL-->>DLF: Current TVL
        DLF-->>HC: >= $5M? GREEN / YELLOW

        Note over HC: Check 4: Exploit check
        HC->>EC: checkExploitsSince(protocol, updatedAt)
        EC->>DL: GET /hacks
        DL-->>EC: Any new entries since updated_at?
        EC-->>HC: GREEN / RED

        Note over HC: Check 5: Contract upgrade (proxies)
        HC->>AF: checkProxyImplementation(chain, address)
        AF->>RPC: Read implementation slot
        RPC-->>AF: Current implementation address
        AF-->>HC: Changed? GREEN / YELLOW
    end

    Note over HC: Generate report
    HC->>HR: generate(allResults)
    HR->>HR: Format per-protocol status + summary
    HR-->>HC: Formatted report

    HC-->>CLI: Exit code 0 (warnings only, never fails build)
    CLI-->>Dev: Print health report + summary
```

---

## 6. Deployment

### 6.1 Packaging

`aya-index` is packaged as a single fat JAR containing all dependencies. It is built with Gradle's `shadowJar` plugin (or equivalent).

```bash
# Build
./gradlew :aya-index:shadowJar

# Run
java -jar aya-index/build/libs/aya-index.jar <command> [options]
```

### 6.2 No Docker

`aya-index` does not require Docker. It is a simple CLI tool that runs on any machine with Java 21+.

### 6.3 CI Integration

| Use Case | Trigger | Command |
|----------|---------|---------|
| Weekly health check | Cron schedule (e.g., every Monday) | `java -jar aya-index.jar health --input aya-txbuilder/src/main/resources/seed/` |
| Pre-release refresh | Manual or release pipeline | `java -jar aya-index.jar refresh --output aya-txbuilder/src/main/resources/seed/` |
| PR validation | On PR that modifies `seed/` | `java -jar aya-index.jar validate --input aya-txbuilder/src/main/resources/seed/` |

### 6.4 Gradle Task Wrappers

```groovy
// In aya-index/build.gradle
task protocolHealth(type: JavaExec) {
    classpath = sourceSets.main.runtimeClasspath
    mainClass = 'aya.index.AyaIndex'
    args = ['health', '--input', '../aya-txbuilder/src/main/resources/seed/']
}

task protocolValidate(type: JavaExec) {
    classpath = sourceSets.main.runtimeClasspath
    mainClass = 'aya.index.AyaIndex'
    args = ['validate', '--input', '../aya-txbuilder/src/main/resources/seed/']
}
```

Invoked via `./gradlew protocolHealth` or `./gradlew protocolValidate`.
