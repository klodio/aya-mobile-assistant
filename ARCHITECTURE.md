# Aya Backend Architecture

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-24

This document provides a visual and structural overview of the Aya backend system. For the full technical specification, see [SPEC.md](SPEC.md).

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Component Diagrams](#2-component-diagrams)
3. [Module Decomposition](#3-module-decomposition)
4. [Data Flow Diagrams](#4-data-flow-diagrams)
5. [Storage Architecture](#5-storage-architecture)
6. [Deployment Model](#6-deployment-model)
7. [Network Topology](#7-network-topology)
8. [Security Architecture](#8-security-architecture)

---

## 1. System Overview

### Design Philosophy

Aya is built around four principles:

1. **Self-contained**: A single fat JAR with embedded SQLite. No Docker, no external database servers, no container orchestration.
2. **Minimal dependencies**: Zero external dependencies by default. Redis is optional for horizontal scaling.
3. **Easy to deploy**: `java -jar aya-backend.jar` on any machine with JDK 21+. No external services required.
4. **Progressive capability**: Phase 1 leverages the mobile's existing functions; Phase 2+ shifts execution to server-generated transactions, upgrading capability without app store releases.

### System Constraints

| Constraint | Impact on Architecture |
|-----------|----------------------|
| Non-custodial | No key storage. All signing happens on mobile. Server only produces unsigned transactions. |
| No user accounts | Public key = identity. No auth database, no sessions tied to accounts. |
| SBE protocol | Binary codec at the API boundary. No JSON serialization layer. |
| SQLite + in-memory state (Redis optional) | No ORM, no migration framework. Simple SQL with embedded driver. |
| Multi-chain | Pluggable chain adapters. Common interface for EVM, Solana, Bitcoin. |
| Topic-restricted | Guardrails are part of the agent pipeline, not a separate service. |

---

## 2. Component Diagrams

### 2.1 C4 Context Diagram

Shows Aya in relation to all external systems.

```mermaid
C4Context
    title Aya Backend — System Context

    Person(user, "Wallet User", "Holds crypto assets, uses mobile wallet")

    System(aya, "Aya Backend", "AI assistant backend serving SBE-encoded requests over HTTP")

    System_Ext(mobile, "React Native Wallet", "Mobile app — signs transactions, renders UI")
    System_Ext(llm, "LLM Providers", "Anthropic, OpenAI, Google — multi-provider")
    System_Ext(market, "Market Data APIs", "CoinGecko, DeFiLlama")
    System_Ext(rpc, "Blockchain RPCs", "EVM, Solana, Bitcoin nodes")
    System_Ext(ayatrade, "Aya Trade", "Own DEX — spot, perps, commodities")
    System_Ext(explorers, "Block Explorers", "Etherscan, Polygonscan, etc. — ABI sources")
    System_Ext(redis, "Redis (optional)", "Only for horizontal scaling — not required by default")

    Rel(user, mobile, "Uses")
    Rel(mobile, aya, "HTTP + SBE", "Binary payloads")
    Rel(aya, llm, "HTTPS", "LLM calls, tool use")
    Rel(aya, market, "HTTPS", "Price, TVL, market data")
    Rel(aya, rpc, "HTTPS/WSS", "Tx simulation, fee estimation, balance checks")
    Rel(aya, ayatrade, "SBE over HTTPS", "Trading, market data")
    Rel(aya, explorers, "HTTPS", "ABI/contract verification")
    Rel(aya, redis, "TCP (if configured)", "Shared state for multi-instance")
```

### 2.2 C4 Container Diagram

Zooms into the Aya backend to show its internal containers.

```mermaid
C4Container
    title Aya Backend — Container Diagram

    Container_Boundary(backend, "Aya Backend (Fat JAR)") {
        Container(api, "API Layer", "Java / HTTP", "SBE codec, auth, rate limiter, request routing")
        Container(agent, "Agent Pipeline", "Java", "LLM orchestration, model routing, tool dispatch, response assembly")
        Container(tools, "Tool Layer", "Java", "Market data, portfolio, news, settings, strategy tools")
        Container(txbuild, "Transaction Builder", "Java", "Protocol index, ABI/IDL registries, protocol adapters, yield discovery, tx construction pipeline")
        Container(exchange, "Aya Trade Client", "Java", "Exchange API integration, priority routing")
        Container(security, "Security Module", "Java", "Signature verification, input sanitization, prompt injection defense")
        ContainerDb(sqlite, "SQLite", "Embedded DB", "Protocol index, ABI/IDL cache, conversation history, token registry")
        ContainerDb(statestore, "StateStore", "In-memory (default) or Redis", "Session state, rate limiting, tool result cache")
    }

    System_Ext(redis, "Redis (optional)", "Only if state.backend=redis for horizontal scaling")
    System_Ext(llm, "LLM Providers", "Multi-provider")
    System_Ext(rpc, "Blockchain RPCs", "EVM, Solana, Bitcoin")
    System_Ext(market, "Market Data APIs", "CoinGecko, DeFiLlama")
    System_Ext(ayatrade, "Aya Trade API", "DEX")

    Rel(api, agent, "Decoded request")
    Rel(api, security, "Auth check")
    Rel(api, statestore, "Rate limiting")
    Rel(agent, tools, "Tool dispatch")
    Rel(agent, txbuild, "Transaction requests")
    Rel(agent, exchange, "Exchange queries")
    Rel(agent, llm, "LLM calls")
    Rel(agent, statestore, "Session load/save")
    Rel(statestore, redis, "If configured", "optional")
    Rel(tools, market, "Market data fetch")
    Rel(txbuild, rpc, "Simulation, fee estimation")
    Rel(txbuild, sqlite, "ABI/IDL cache")
    Rel(exchange, ayatrade, "Order placement, market data")
    Rel(agent, sqlite, "Conversation history")
```

### 2.3 C4 Component Diagram — API Layer

```mermaid
graph TB
    subgraph "API Layer (aya-server)"
        HTTP[HTTP Server<br/>Netty]
        CODEC[SBE Codec<br/>Encode/Decode]
        AUTH[Auth Verifier<br/>ECDSA secp256k1]
        RATE[Rate Limiter<br/>In-memory (Redis optional)]
        ROUTER[Request Router<br/>Dispatches to Agent Pipeline]
        HEALTH[Health Endpoint<br/>GET /health]
    end

    CLIENT[Client Request] --> HTTP
    HTTP --> CODEC
    CODEC --> AUTH
    AUTH --> RATE
    RATE --> ROUTER
    ROUTER --> PIPELINE[Agent Pipeline]
    HTTP --> HEALTH
```

### 2.4 C4 Component Diagram — Agent Pipeline

The LLM is the orchestrator. There is no separate intent classifier — the LLM decides what to do via tool calling.

```mermaid
graph TB
    subgraph "Agent Pipeline (aya-agent)"
        CONVMGR[Conversation Manager<br/>Session load/save, summarization]
        TIERSELECT[Tier Selector<br/>Simple keyword heuristic]
        LLMCALL[LLM Call<br/>System prompt + history + tools]
        EXECUTOR[Tool Executor<br/>Runs tool calls requested by LLM]
        ENCODER[Response Encoder<br/>Map LLM output to SBE messages]
    end

    REQUEST[Decoded Request] --> CONVMGR
    CONVMGR --> TIERSELECT
    TIERSELECT --> LLMCALL
    LLMCALL -->|tool calls| EXECUTOR
    EXECUTOR -->|results| LLMCALL
    LLMCALL -->|final response| ENCODER
    ENCODER --> RESPONSE[SBE Response]

    EXECUTOR --> TOOLS[Tool Layer]
    EXECUTOR --> TXBUILD[Transaction Builder]
    CONVMGR --> STATESTORE[(StateStore)]
    CONVMGR --> SQLITE[(SQLite)]
    LLMCALL --> LLM[LLM Providers]
```

Note the loop: the LLM calls tools, receives results, and may call more tools before producing a final response. This is a standard agentic loop — the LLM drives the conversation and tool orchestration.

### 2.5 C4 Component Diagram — Transaction Builder

```mermaid
graph TB
    subgraph "Transaction Builder (aya-txbuilder)"
        direction TB
        subgraph "Protocol Index (pre-populated + on-demand)"
            PROTOREG[Protocol Registry<br/>Protocols, chains, actions, APY, TVL]
            ABIREG[ABI Registry<br/>Bundled + on-demand EVM ABIs]
            IDLREG[IDL Registry<br/>Bundled + on-demand Solana IDLs]
            TOKENREG[Token Registry<br/>Address resolution]
        end
        subgraph "Discovery Tools (LLM-callable)"
            SEARCH[search_protocols<br/>Query by category/chain/asset]
            YIELD[get_best_yield<br/>Ranked yield opportunities]
            PROTOINFO[get_protocol_info<br/>Protocol details]
        end
        subgraph "Adapter Layer"
            UNISWAP[Uniswap V3 Adapter]
            AAVE[Aave V3 Adapter]
            LIDO[Lido Adapter]
            JUPITER[Jupiter Adapter]
            MARINADE[Marinade Adapter]
            ONEINCH[1inch Adapter]
            LIFI[LiFi Adapter]
            AYATRADE_ADAPTER[Aya Trade Adapter]
        end
        subgraph "Pipeline Layer"
            SELECTOR[Protocol Selector<br/>Aya Trade priority]
            RESOLVER[Parameter Resolver<br/>Addresses, balances, approvals]
            BUILDER[Transaction Builder<br/>Calldata/instruction encoding]
            SIMULATOR[Simulator<br/>eth_call / simulateTransaction]
            ESTIMATOR[Fee Estimator<br/>Gas + safety margin]
            SERIALIZER[Serializer<br/>TransactionBundle encoding]
        end
    end

    INTENT[User Intent / LLM Tool Call] --> SEARCH
    INTENT --> YIELD
    INTENT --> SELECTOR
    SEARCH --> PROTOREG
    YIELD --> PROTOREG
    YIELD --> DEFILLAMA[DeFiLlama<br/>Live APY/TVL]
    PROTOINFO --> PROTOREG

    SELECTOR --> RESOLVER
    RESOLVER --> BUILDER
    BUILDER --> SIMULATOR
    SIMULATOR --> ESTIMATOR
    ESTIMATOR --> SERIALIZER
    SERIALIZER --> BUNDLE[TransactionBundle]

    BUILDER --> ABIREG
    BUILDER --> IDLREG
    RESOLVER --> TOKENREG
    SIMULATOR --> RPC[Blockchain RPCs]
    PROTOREG --> SQLITE[(SQLite<br/>Bundled seed + runtime cache)]
    ABIREG --> SQLITE
    ABIREG --> EXPLORERS[Block Explorers<br/>On-demand ABI fetch]
```

Key design: The Protocol Index is **pre-populated** with bundled seed data (YAML + ABI/IDL files shipped in the JAR). No background daemon. Live APY/TVL comes from DeFiLlama at query time. On-demand ABI fetch from block explorers for unknown contracts.

---

## 3. Module Decomposition

### Module Dependency Graph

```mermaid
graph LR
    PROTO[aya-protocol] --> SERVER[aya-server]
    PROTO --> AGENT[aya-agent]
    PROTO --> TXBUILD[aya-txbuilder]
    PROTO --> CLI[aya-cli]
    SECURITY[aya-security] --> SERVER
    AGENT --> SERVER
    TOOLS[aya-tools] --> AGENT
    TXBUILD --> AGENT
    EXCHANGE[aya-exchange] --> AGENT
    EXCHANGE --> TXBUILD
    INDEX[aya-index] -.-> TXBUILD
    CLI --> BDD[aya-bdd]
    BDD -.-> SERVER
    BDD -.-> AGENT
    BDD -.-> TOOLS
    BDD -.-> TXBUILD
```

*Solid arrows = compile dependency. Dashed arrows = test or offline dependency.*

**`aya-cli`** (test client) and **`aya-index`** (seed data tool) are **separate modules with separate JARs**. `aya-cli` communicates with the backend over HTTP+SBE for testing. `aya-index` fetches ABIs/IDLs/metadata from external sources to populate the protocol index seed data — it runs offline and never talks to the backend.

### Module Details

#### aya-protocol

| Aspect | Detail |
|--------|--------|
| **Purpose** | SBE schema definition and code generation |
| **Responsibilities** | Define all SBE message types, enums, composites. Generate Java encoders/decoders. Generate TypeScript codecs for the React Native client. |
| **Key Artifacts** | `aya-assistant.xml` (schema), generated `*Encoder`/`*Decoder` classes |
| **Dependencies** | SBE Tool (build-time only) |
| **Consumers** | Every other module imports generated codecs |

#### aya-server

| Aspect | Detail |
|--------|--------|
| **Purpose** | HTTP endpoint and request lifecycle management |
| **Responsibilities** | Netty-based HTTP server accepting POST with SBE body. Decode request. Verify signature. Check rate limit. Route to agent pipeline. Encode response. Serve health endpoint. WebSocket endpoint (Phase 2). |
| **Key Interfaces** | `RequestHandler`, `ResponseWriter` |
| **Dependencies** | `aya-protocol`, `aya-security`, `aya-agent` |
| **External** | Redis (rate limiting, if configured) |

#### aya-agent

| Aspect | Detail |
|--------|--------|
| **Purpose** | Core agent logic: orchestrates the LLM and tool execution loop |
| **Responsibilities** | Model tier selection (simple heuristic). LLM call management (system prompt, history, tools). Tool execution when requested by the LLM. Agentic loop (LLM → tools → LLM). Response encoding to SBE. Conversation state management (load, save, summarize). The LLM itself handles intent understanding, disambiguation, confirmation, disclaimers, and off-topic refusal. |
| **Key Interfaces** | `AgentPipeline`, `ModelRouter`, `ToolExecutor`, `ResponseEncoder`, `ConversationManager` |
| **Dependencies** | `aya-protocol`, `aya-tools`, `aya-txbuilder`, `aya-exchange` |
| **External** | LLM providers, StateStore (session state — in-memory or Redis if configured), SQLite (conversation history) |

#### aya-tools

| Aspect | Detail |
|--------|--------|
| **Purpose** | Implementations of all tools the LLM can call |
| **Responsibilities** | Market data retrieval and caching. Portfolio analysis. News aggregation. Settings change construction. Trading strategy generation. Token info lookup. |
| **Key Interfaces** | `Tool`, `ToolRegistry` |
| **Dependencies** | None (tools are self-contained) |
| **External** | CoinGecko, DeFiLlama, news APIs, StateStore (tool result cache — in-memory or Redis if configured) |

#### aya-txbuilder

| Aspect | Detail |
|--------|--------|
| **Purpose** | Protocol index, yield discovery, and transaction construction for all supported chains |
| **Responsibilities** | Pre-populated protocol index (registry of protocols, chains, actions, APYs). ABI/IDL storage (bundled seed + on-demand fetch). Protocol adapter management. Discovery tools for the LLM (`search_protocols`, `get_best_yield`, `get_protocol_info`). Transaction construction pipeline (resolve, build, simulate, estimate, serialize). Multi-step sequence orchestration. |
| **Key Interfaces** | `ChainAdapter`, `ProtocolAdapter`, `ProtocolIndex`, `AbiRegistry`, `IdlRegistry`, `TransactionPipeline` |
| **Dependencies** | `aya-protocol` |
| **External** | Blockchain RPCs, block explorer APIs (on-demand ABI fetch), DeFiLlama (live APY/TVL), SQLite (protocol index + ABI/IDL cache) |

#### aya-exchange

| Aspect | Detail |
|--------|--------|
| **Purpose** | Aya Trade exchange integration |
| **Responsibilities** | Wrap Aya Trade's SBE-based API. Implement priority routing logic. Place orders (spot, perps, commodities). Fetch order book and market data. |
| **Key Interfaces** | `AyaTradeClient`, `ExchangeRouter` |
| **Dependencies** | `aya-protocol` (Aya Trade uses SBE) |
| **External** | Aya Trade API |

#### aya-security

| Aspect | Detail |
|--------|--------|
| **Purpose** | Authentication, input validation, and safety checks |
| **Responsibilities** | ECDSA secp256k1 signature verification. Timestamp freshness validation. Prompt injection detection. Output validation (no system prompt leakage). Contract blacklist management. |
| **Key Interfaces** | `SignatureVerifier`, `InputValidator`, `OutputValidator`, `ContractBlacklist` |
| **Dependencies** | None |
| **External** | SQLite (blacklist table) |

#### aya-index

| Aspect | Detail |
|--------|--------|
| **Purpose** | Offline tool for bootstrapping, auditing, and monitoring the protocol index |
| **Responsibilities** | **Seed management**: Fetch ABIs from block explorers, IDLs from Solana, TVL/APY from DeFiLlama. Write seed YAML and ABI/IDL files. Validate completeness. **Audit**: Automated due diligence for new protocol proposals (TVL, audits, exploits, activity). **Health monitor**: Ongoing checks for contract liveness, ABI validity, TVL decline, exploit detection, proxy upgrades. |
| **Key Interfaces** | `AbiFetcher`, `IdlFetcher`, `DefiLlamaFetcher`, `SeedWriter`, `SeedValidator`, `ProtocolAuditor`, `HealthChecker` |
| **Commands** | `refresh`, `add`, `validate`, `list`, `audit`, `health` |
| **Dependencies** | None (standalone — reads/writes seed files, calls external APIs) |
| **External** | Block explorer APIs, DeFiLlama API (protocol data + hacks endpoint + yields), Solana RPC, GitHub API (activity check), rekt.news |
| **Runs** | Offline only — developer machine or CI. `audit` and `health` can run as CI cron jobs. Never runs at runtime. |

#### aya-cli

| Aspect | Detail |
|--------|--------|
| **Purpose** | CLI test client for manual and automated testing |
| **Responsibilities** | Interactive REPL for developers. Script mode for batch testing. TestHarness Java API for BDD step definitions. SBE encoding/decoding, request signing, portfolio simulation, response rendering. |
| **Key Interfaces** | `AyaHttpClient`, `AyaWsClient`, `TestHarness`, `ReplEngine`, `ScriptRunner` |
| **Dependencies** | `aya-protocol` (SBE codecs) |
| **External** | Aya Backend (via HTTP+SBE) |

#### aya-bdd

| Aspect | Detail |
|--------|--------|
| **Purpose** | Cucumber BDD test infrastructure |
| **Responsibilities** | Step definitions for all feature files. Test fixtures and helpers. WireMock stubs for external services. Integration test configuration. |
| **Key Artifacts** | `features/*.feature`, step definition classes |
| **Dependencies** | `aya-cli` (TestHarness), all backend modules (test scope) |

---

## 4. Data Flow Diagrams

### 4.1 Request Lifecycle

The LLM is the orchestrator — there is no separate intent classifier or tool selector.

```mermaid
sequenceDiagram
    participant Client as React Native
    participant API as API Layer
    participant Auth as Security
    participant Rate as Rate Limiter
    participant Conv as Conversation Mgr
    participant Tier as Tier Selector
    participant LLM as LLM Provider
    participant Tools as Tool Executor
    participant Encode as Response Encoder

    Client->>API: HTTP POST (SBE binary body)
    API->>API: SBE Decode AssistantRequest
    API->>Auth: Verify signature(publicKey, signature, payload)
    Auth-->>API: Valid / Invalid

    alt Invalid signature
        API-->>Client: ErrorResponse(AUTH)
    end

    API->>Rate: Check rate limit(publicKey)
    Rate-->>API: Allowed / Denied

    alt Rate limited
        API-->>Client: ErrorResponse(RATE_LIMIT, retryable=true)
    end

    API->>Conv: Load session(sessionId)
    Conv-->>API: Conversation history

    API->>Tier: Select model tier(message keywords)
    Tier-->>API: Tier 1 (fast) or Tier 2 (powerful)

    API->>LLM: system prompt + history + message + all tool definitions

    loop Agentic loop (LLM decides)
        LLM-->>API: Tool call request (e.g., get_price, build_transaction)
        API->>Tools: Execute tool
        Tools-->>API: Tool result
        API->>LLM: Tool result
    end

    LLM-->>API: Final response (text + optional structured data)

    API->>Encode: Map LLM output to SBE messages
    Encode->>API: SBE Encode AssistantResponse
    API-->>Client: HTTP 200 (SBE binary body)

    API->>Conv: Save turn(session, message, response, tool_calls)
```

Note: The LLM naturally handles intent understanding, disambiguation ("Which UNI do you mean?"), confirmation ("Shall I proceed?"), off-topic refusal, disclaimers, and language matching — all through the system prompt and conversation context. No custom state machines are needed.

### 4.2 Transaction Builder Pipeline

```mermaid
sequenceDiagram
    participant Agent as Agent Pipeline
    participant Selector as Protocol Selector
    participant AyaTrade as Aya Trade Check
    participant Adapter as Protocol Adapter
    participant Registry as ABI/IDL Registry
    participant RPC as Blockchain RPC
    participant Estimator as Fee Estimator

    Agent->>Selector: Build transaction(intent: SWAP 100 USDC → ETH, chain: Polygon)

    Selector->>AyaTrade: Is USDC/ETH available?
    AyaTrade-->>Selector: No (or insufficient liquidity)

    Selector->>Selector: Select Uniswap V3 on Polygon

    Selector->>Adapter: resolveParameters(intent, chainContext)
    Adapter->>Registry: Get ABI for SwapRouter02
    Registry-->>Adapter: ABI (from cache or Polygonscan)
    Adapter->>RPC: Check USDC allowance for router
    RPC-->>Adapter: Allowance = 0

    Adapter->>Adapter: Build approve() calldata
    Adapter->>Adapter: Build exactInputSingle() calldata
    Adapter-->>Selector: [approve_tx, swap_tx]

    Selector->>RPC: eth_call (simulate approve)
    RPC-->>Selector: Success
    Selector->>RPC: eth_call (simulate swap)
    RPC-->>Selector: Success, output = 0.032 WETH

    Selector->>Estimator: Estimate fees
    Estimator->>RPC: eth_estimateGas (approve)
    RPC-->>Estimator: 46000 gas
    Estimator->>RPC: eth_estimateGas (swap)
    RPC-->>Estimator: 185000 gas
    Estimator-->>Selector: Total = (46000 + 185000) * 1.2 * gasPrice

    Selector-->>Agent: TransactionBundle(chainId=Polygon, 2 txs, fee, simulationPassed=true)
```

### 4.3 Conversation Flow

No state machines — the LLM drives disambiguation and confirmation through natural conversation. The server only manages session storage.

```mermaid
sequenceDiagram
    participant User as User
    participant Server as Server
    participant LLM as LLM
    participant Store as StateStore

    Note over User,Store: Turn 1 — Ambiguous request

    User->>Server: "Buy USDC" (no sessionId)
    Server->>Server: Generate sessionId
    Server->>LLM: system prompt + "Buy USDC" + tools
    LLM-->>Server: "USDC exists on multiple chains. Which do you prefer?"
    Note right of LLM: LLM naturally disambiguates.<br/>No state machine needed.
    Server->>Store: Save turn
    Server->>User: "USDC exists on multiple chains..."

    Note over User,Store: Turn 2 — User clarifies

    User->>Server: "Polygon, 100 dollars worth"
    Server->>Store: Load history (Turn 1)
    Server->>LLM: history + "Polygon, 100 dollars worth" + tools
    LLM->>LLM: Calls get_price(USDC, Polygon), check_aya_trade(USDC/ETH)
    LLM-->>Server: "I'll buy ~100 USDC on Polygon. Fee: ~0.01 POL. Proceed?"
    Note right of LLM: LLM naturally confirms.<br/>No state machine needed.
    Server->>Store: Save turn
    Server->>User: "I'll buy ~100 USDC on Polygon..."

    Note over User,Store: Turn 3 — User confirms

    User->>Server: "Yes"
    Server->>Store: Load history (Turns 1-2)
    Server->>LLM: history + "Yes" + tools
    LLM->>LLM: Calls build_transaction(...)
    LLM-->>Server: "Done! Here's the transaction to sign." + TransactionBundle
    Server->>Store: Save turn
    Server->>User: TransactionBundle

    Note over User,Store: Context summarization (after 20+ turns)

    Server->>Store: Load turns
    Server->>LLM: "Summarize this conversation"
    LLM-->>Server: Summary
    Server->>Store: Replace old turns with summary, keep last 10
```

---

## 5. Storage Architecture

### 5.1 SQLite Schema

SQLite is used for persistent, local data. The database file is created automatically on first run.

```sql
-- Protocol Registry: Queryable index of all known DeFi protocols
-- Pre-populated from bundled seed data, augmented with live APY/TVL
CREATE TABLE protocol_registry (
    protocol_id     TEXT NOT NULL,
    protocol_name   TEXT NOT NULL,
    chain_id        INTEGER NOT NULL,
    category        TEXT NOT NULL,         -- 'dex', 'lending', 'staking', 'bridge', 'yield', 'perps'
    actions         TEXT NOT NULL,         -- comma-separated: 'swap,liquidity'
    tvl_usd         TEXT,
    apy_current     TEXT,
    apy_7d_avg      TEXT,
    risk_level      TEXT,                  -- 'low', 'medium', 'high'
    website         TEXT,
    description     TEXT,
    updated_at      INTEGER NOT NULL,
    PRIMARY KEY (protocol_id, chain_id)
);
CREATE INDEX idx_protocol_category ON protocol_registry(category);
CREATE INDEX idx_protocol_chain ON protocol_registry(chain_id);

-- Protocol Contracts: Maps protocols to their contract addresses
CREATE TABLE protocol_contracts (
    protocol_id     TEXT NOT NULL,
    chain_id        INTEGER NOT NULL,
    contract_name   TEXT NOT NULL,
    address         TEXT NOT NULL,
    PRIMARY KEY (protocol_id, chain_id, contract_name)
);

-- ABI Registry: Bundled + on-demand EVM contract ABIs
CREATE TABLE abi_registry (
    chain_id        INTEGER NOT NULL,
    address         TEXT NOT NULL,         -- lowercase, 0x-prefixed
    abi_json        TEXT NOT NULL,
    source          TEXT NOT NULL,         -- 'bundled', 'etherscan', 'manual'
    verified        INTEGER NOT NULL,      -- 1 = verified on explorer
    fetched_at      INTEGER NOT NULL,
    PRIMARY KEY (chain_id, address)
);

-- IDL Registry: Bundled + on-demand Solana program IDLs
CREATE TABLE idl_registry (
    program_address TEXT NOT NULL PRIMARY KEY,
    idl_json        TEXT NOT NULL,
    source          TEXT NOT NULL,         -- 'bundled', 'onchain', 'deploydao', 'manual'
    fetched_at      INTEGER NOT NULL,
    anchor_version  TEXT
);

-- Conversation History: Full turn-by-turn record
CREATE TABLE conversation_history (
    session_id      TEXT NOT NULL,
    turn_index      INTEGER NOT NULL,
    role            TEXT NOT NULL,         -- 'USER', 'ASSISTANT', 'SYSTEM'
    content         TEXT NOT NULL,
    timestamp       INTEGER NOT NULL,      -- epoch milliseconds
    metadata_json   TEXT,                  -- tools used, actions returned, intent
    PRIMARY KEY (session_id, turn_index)
);
CREATE INDEX idx_conv_session ON conversation_history(session_id);
CREATE INDEX idx_conv_timestamp ON conversation_history(timestamp);

-- Token Registry: Known tokens across all chains
CREATE TABLE token_registry (
    chain_id        INTEGER NOT NULL,
    contract_address TEXT NOT NULL,        -- empty string for native tokens
    symbol          TEXT NOT NULL,
    name            TEXT NOT NULL,
    decimals        INTEGER NOT NULL,
    market_cap      TEXT,                  -- decimal string, updated periodically
    verified        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (chain_id, contract_address)
);
CREATE INDEX idx_token_symbol ON token_registry(symbol);

-- Contract Blacklist: Known malicious contracts
CREATE TABLE contract_blacklist (
    chain_id        INTEGER NOT NULL,
    address         TEXT NOT NULL,         -- lowercase, 0x-prefixed
    reason          TEXT NOT NULL,
    added_at        INTEGER NOT NULL,      -- epoch seconds
    PRIMARY KEY (chain_id, address)
);

-- Market Data Cache: Persistent cache for market data
CREATE TABLE market_data_cache (
    cache_key       TEXT NOT NULL PRIMARY KEY,
    data_json       TEXT NOT NULL,
    fetched_at      INTEGER NOT NULL,      -- epoch seconds
    ttl_seconds     INTEGER NOT NULL
);
```

### 5.2 StateStore Cache Patterns

These patterns apply to the StateStore abstraction. With the default in-memory backend, keys live in a `ConcurrentHashMap` with TTL-based eviction. When `state.backend: redis` is configured, they map to Redis keys.

| Pattern | Purpose | TTL |
|---------|---------|-----|
| `aya:session:{sessionId}` | Active session state (recent turns, disambiguation, pending confirmation) | 24 hours |
| `aya:rate:{publicKey}` | Sliding window rate limit counter | 60 seconds |
| `aya:rate:global` | Global rate limit counter | 60 seconds |
| `aya:cache:tool:{toolName}:{paramHash}` | Tool result cache (market data, token info) | 30s–1h (varies by tool) |
| `aya:circuit:{providerName}` | Circuit breaker state for LLM providers | 30 seconds |

### 5.3 Storage Decision Matrix

| Data | Storage | Rationale |
|------|---------|-----------|
| Protocol registry | SQLite | Pre-populated seed, queryable by LLM tools, read-heavy |
| Protocol contracts | SQLite | Maps protocols to addresses, bundled with seed |
| ABI/IDL cache | SQLite | Bundled seed + on-demand fetch, read-heavy |
| Conversation history | SQLite + StateStore | Recent turns in StateStore (in-memory or Redis), full history in SQLite (persistent) |
| Session state | StateStore (in-memory or Redis) | Ephemeral, needs fast access. Redis backend enables cross-instance sharing. |
| Rate limiting | StateStore (in-memory or Redis) | In-memory by default. Redis backend enables shared limits across instances. |
| Token registry | SQLite | Persistent reference data, read-heavy |
| Contract blacklist | SQLite | Persistent, rarely written, frequently read |
| Tool result cache | StateStore (in-memory or Redis) | Short-lived. Redis backend enables sharing across instances. |
| Live APY/TVL | StateStore (in-memory or Redis) | Cached from DeFiLlama, short TTL (5 min), augments seed data |

---

## 6. Deployment Model

### 6.1 Artifact

The build produces a single **fat JAR** containing all compiled classes, dependencies, and resources:

```
aya-server/build/libs/aya-backend.jar  (~50-100 MB)
```

Built via Gradle Shadow plugin (or Spring Boot's bootJar):
```bash
./gradlew shadowJar    # or ./gradlew bootJar
```

### 6.2 Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| JDK | 21+ | Eclipse Temurin, GraalVM, or any OpenJDK distribution |
| Redis | 6+ (optional) | Only needed if `state.backend: redis` for horizontal scaling |

**Not required**: Docker, PostgreSQL, Redis (unless scaling horizontally), Kubernetes, or any other infrastructure.

### 6.3 Running

```bash
# Minimal (in-memory state, zero external deps)
java -jar aya-backend.jar

# With Redis for horizontal scaling
# java -jar aya-backend.jar --state.backend=redis --redis.url=redis://localhost:6379

# With all configuration
java -jar aya-backend.jar \
  --server.port=8080 \
  --llm.providers.0.apiKey=sk-ant-... \
  --llm.providers.1.apiKey=sk-... \
  --coingecko.pro.apiKey=CG-... \
  --rpc.ethereum.url=https://eth-mainnet.g.alchemy.com/v2/... \
  --rpc.polygon.url=https://polygon-mainnet.g.alchemy.com/v2/... \
  --rpc.solana.url=https://api.mainnet-beta.solana.com
```

### 6.4 Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `PORT` | 8080 | HTTP server port |
| `REDIS_URL` | redis://localhost:6379 | Redis connection URL (only used if `state.backend=redis`) |
| `SQLITE_PATH` | ./aya.db | SQLite database file path |
| `ANTHROPIC_API_KEY` | — | Anthropic API key |
| `OPENAI_API_KEY` | — | OpenAI API key |
| `COINGECKO_PRO_API_KEY` | — | CoinGecko Pro API key |
| `ETH_RPC_URL` | — | Ethereum RPC endpoint |
| `POLYGON_RPC_URL` | — | Polygon RPC endpoint |
| `ARBITRUM_RPC_URL` | — | Arbitrum RPC endpoint |
| `SOLANA_RPC_URL` | — | Solana RPC endpoint |
| `AYA_TRADE_API_URL` | — | Aya Trade API endpoint (Phase 2+) |
| `LOG_LEVEL` | INFO | Logging level |

Also configurable via `application.yml` in the working directory.

### 6.5 Horizontal Scaling

```mermaid
graph TB
    LB[Load Balancer]
    LB --> I1[Instance 1<br/>aya-backend.jar]
    LB --> I2[Instance 2<br/>aya-backend.jar]
    LB --> I3[Instance 3<br/>aya-backend.jar]

    I1 --> REDIS[(Redis<br/>Shared session state<br/>when state.backend=redis)]
    I2 --> REDIS
    I3 --> REDIS

    I1 --> S1[(SQLite 1<br/>Local cache)]
    I2 --> S2[(SQLite 2<br/>Local cache)]
    I3 --> S3[(SQLite 3<br/>Local cache)]
```

- **Redis** (required for multi-instance): When `state.backend: redis` is configured, Redis is shared across all instances for session state, rate limiting, and caching.
- **SQLite**: Per-instance. ABI/IDL caches are read-heavy and safe to duplicate. Conversation history is written to both StateStore and SQLite; SQLite is per-instance but Redis (when configured) ensures cross-instance session continuity.
- **Sticky sessions**: Not required when using Redis backend. Any instance can serve any request because session state is in Redis. With the default in-memory backend, sticky sessions are required or a single instance must be used.

### 6.6 Health Endpoint

```
GET /health
```

Response (200 OK):
```json
{
  "status": "healthy",
  "state_backend": "memory",
  "sqlite": "ok",
  "llm_providers": {
    "anthropic": "available",
    "openai": "available"
  },
  "uptime_seconds": 86400
}
```

Returns 503 if all LLM providers are down (or Redis is unreachable when `state.backend: redis`).

---

## 7. Network Topology

### 7.1 Full Topology Diagram

```mermaid
graph LR
    subgraph "Client Network"
        MOBILE[React Native Wallet]
    end

    subgraph "Aya Infrastructure"
        LB[Load Balancer<br/>HTTPS termination]
        subgraph "Backend Instances"
            I1[Instance 1]
            I2[Instance 2]
        end
        REDIS[(Redis<br/>optional)]
    end

    subgraph "External Services"
        LLM_A[Anthropic API]
        LLM_O[OpenAI API]
        CG[CoinGecko API]
        DFL[DeFiLlama API]
        ETH_RPC[Ethereum RPC]
        SOL_RPC[Solana RPC]
        BTC_RPC[Bitcoin/Mempool API]
        ESCAN[Etherscan API]
        AYATRADE[Aya Trade API]
    end

    MOBILE -->|HTTPS + SBE| LB
    LB --> I1
    LB --> I2
    I1 -.->|if configured| REDIS
    I2 -.->|if configured| REDIS

    I1 -->|HTTPS| LLM_A
    I1 -->|HTTPS| LLM_O
    I1 -->|HTTPS| CG
    I1 -->|HTTPS| DFL
    I1 -->|HTTPS/WSS| ETH_RPC
    I1 -->|HTTPS| SOL_RPC
    I1 -->|HTTPS| BTC_RPC
    I1 -->|HTTPS| ESCAN
    I1 -->|SBE/HTTPS| AYATRADE
```

### 7.2 Protocol Summary

| Connection | Protocol | Encoding | Notes |
|-----------|----------|----------|-------|
| Client ↔ Backend | HTTP/1.1 (Phase 1), WebSocket (Phase 2) | SBE binary | TLS terminated at load balancer |
| Backend → LLM providers | HTTPS | JSON (provider APIs) | Connection pooled |
| Backend → Market APIs | HTTPS | JSON | Connection pooled, responses cached |
| Backend → Blockchain RPCs | HTTPS or WSS | JSON-RPC | Per-chain connection pool |
| Backend → Block explorers | HTTPS | JSON | Rate-limited by explorer |
| Backend → Aya Trade | HTTPS | SBE binary | Same encoding as our protocol |
| Backend ↔ Redis (if configured) | TCP | RESP protocol | Connection pooled (16 connections default) |

### 7.3 Connection Pooling

| Target | Pool Size | Keep-Alive | Notes |
|--------|-----------|------------|-------|
| LLM providers | 10 per provider | Yes | Reuses connections for sequential model calls |
| Blockchain RPCs | 5 per chain | Yes | WebSocket for subscription data (Phase 2+) |
| Market APIs | 5 per API | Yes | Short-lived requests, cached results |
| Redis (if configured) | 16 | Yes | Jedis or Lettuce pool |
| SQLite | 1 | N/A | Single connection, WAL mode for concurrent reads |

---

## 8. Security Architecture

### 8.1 Authentication Flow

```mermaid
sequenceDiagram
    participant Client as React Native
    participant Server as Aya Backend

    Note over Client: User composes message
    Client->>Client: Serialize SBE payload (without signature)
    Client->>Client: Sign payload with private key (ECDSA secp256k1)
    Client->>Client: Attach publicKey + signature to AssistantRequest

    Client->>Server: HTTP POST (SBE binary)

    Server->>Server: Extract publicKey and signature from envelope
    Server->>Server: Extract payload bytes (the signed portion)
    Server->>Server: Verify ECDSA signature(publicKey, signature, payload)

    alt Signature valid
        Server->>Server: Check timestamp freshness (within ±5 minutes)
        Server->>Server: Proceed with request processing
    else Signature invalid or missing
        Server-->>Client: ErrorResponse(AUTH)
    end
```

### 8.2 Threat Model

| Threat | Impact | Likelihood | Mitigation |
|--------|--------|-----------|------------|
| **Prompt injection** | LLM generates off-topic content, reveals system prompt | High | System prompt isolation, output validation, input pattern detection |
| **Replay attack** | Attacker resends captured requests | Medium | Timestamp freshness check (±5 min window) |
| **Portfolio spoofing** | User claims false balances | Medium | RPC balance verification for transactions (Phase 2+) |
| **Scam contract interaction** | User tricked into signing malicious transaction | Medium | Contract blacklist, unverified contract warnings, simulation |
| **Rate limit abuse** | DoS via excessive requests | High | Per-key and global rate limiting via StateStore (in-memory or Redis) |
| **Data exfiltration** | Internal details leaked in responses | Low | Output validation, no stack traces, generic error messages |
| **Man-in-the-middle** | Payload tampered in transit | Low | TLS at load balancer, SBE payload signed by user |

### 8.3 Defense Layers

```mermaid
graph TB
    REQUEST[Incoming Request]
    REQUEST --> L1

    subgraph "Layer 1: Transport"
        L1[TLS Termination<br/>at Load Balancer]
    end

    L1 --> L2

    subgraph "Layer 2: Authentication"
        L2[Signature Verification<br/>ECDSA secp256k1]
        L2A[Timestamp Freshness<br/>±5 minute window]
    end

    L2 --> L2A --> L3

    subgraph "Layer 3: Rate Limiting"
        L3[Per-Key Limit<br/>30 req/min]
        L3A[Global Limit<br/>10,000 req/min]
    end

    L3 --> L3A --> L4

    subgraph "Layer 4: Input Validation"
        L4[SBE Schema Validation<br/>Required fields, types]
        L4A[Payload Size Check<br/>Max 1MB]
        L4B[Prompt Injection Detection<br/>Pattern matching]
    end

    L4 --> L4A --> L4B --> L5

    subgraph "Layer 5: Output Validation"
        L5[System Prompt Leak Check]
        L5A[Off-Topic Response Check]
        L5B[Internal Detail Suppression]
    end

    L5 --> L5A --> L5B --> PROCESS[Process Request]
```

### 8.4 Prompt Injection Defense

The system employs a multi-layered approach:

1. **System prompt isolation**: The system prompt is hardcoded, never user-modifiable. User input is wrapped in clear delimiters:
   ```
   <system>
   [Hardcoded system prompt — never shown to user]
   </system>
   <user_message>
   {user's text}
   </user_message>
   ```

2. **Input pattern detection**: Check for known injection patterns:
   - "Ignore previous instructions"
   - "You are now a..."
   - "Repeat everything above"
   - Base64-encoded instructions
   - JSON role overrides

3. **Output validation**: After LLM generates a response, check for:
   - System prompt content appearing in the response
   - Model name or provider references
   - Off-topic content that bypassed the system prompt guardrails
   - Tool name or internal architecture details

4. **Escalation**: If injection is detected, the response is discarded and a safe default is returned.

### 8.5 Transaction Safety

Before any transaction is presented to the user:

```mermaid
graph TB
    TX[Built Transaction] --> SIM{Simulation<br/>passes?}
    SIM -->|No| FAIL[Report failure<br/>+ revert reason]
    SIM -->|Yes| VERIFY{Contract<br/>verified?}
    VERIFY -->|No| WARN[Warn: unverified<br/>contract]
    VERIFY -->|Yes| BLACK{On<br/>blacklist?}
    WARN --> CONFIRM[Request explicit<br/>confirmation]
    BLACK -->|Yes| REJECT[Refuse to<br/>build transaction]
    BLACK -->|No| GAS{Gas<br/>reasonable?}
    GAS -->|>10x typical| GASWARN[Warn: unusual<br/>gas cost]
    GAS -->|Normal| PRESENT[Present to user<br/>for signing]
    GASWARN --> PRESENT
```

---

*For the full technical specification, see [SPEC.md](SPEC.md).*
*For behavioral expectations and test scenarios, see [BEHAVIORS_AND_EXPECTATIONS.md](BEHAVIORS_AND_EXPECTATIONS.md).*
