# Aya CLI Test Client — Technical Specification

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-24
**Parent**: [SPEC.md](SPEC.md) (Aya Backend Specification)

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Overview](#2-system-overview)
3. [Module Structure](#3-module-structure)
4. [Key Management](#4-key-management)
5. [SBE Protocol Client](#5-sbe-protocol-client)
6. [HTTP Transport](#6-http-transport)
7. [WebSocket Transport](#7-websocket-transport)
8. [Interactive Mode (REPL)](#8-interactive-mode-repl)
9. [Script Mode](#9-script-mode)
10. [Portfolio Simulation](#10-portfolio-simulation)
11. [Response Rendering](#11-response-rendering)
12. [Integration Test Harness](#12-integration-test-harness)
13. [Configuration](#13-configuration)
14. [Testing Strategy](#14-testing-strategy)

---

## 1. Introduction

### 1.1 Purpose

The Aya CLI Test Client (`aya-cli`) is a Java command-line tool that communicates with the Aya backend over HTTP+SBE, exactly as the React Native mobile client would. It serves two purposes:

1. **Manual testing**: An interactive REPL for developers to converse with the backend, inspect SBE-decoded responses, simulate portfolios, and test every feature by hand.
2. **Automated testing**: A programmable harness that the integration and BDD test suites use to send real HTTP requests to a running backend and assert on the SBE-decoded responses.

### 1.2 Scope

The CLI client:

- Generates and manages ECDSA secp256k1 key pairs (same as a real wallet)
- Encodes requests as SBE binary and sends them over HTTP POST
- Decodes SBE binary responses and renders them as human-readable text
- Connects via WebSocket for streaming responses (Phase 2)
- Simulates user portfolios (configurable balances for testing)
- Signs requests with the user's private key (like the mobile app)
- Simulates transaction signing (accept/reject/broadcast mock)
- Runs in interactive (REPL) mode or script (batch) mode
- Provides a Java API used by Cucumber step definitions for BDD integration tests

### 1.3 What It Is Not

- Not a production client — no wallet UI, no real key storage, no real broadcasting
- Not a load testing tool (use JMH or k6 for that)
- Not a mock server — it talks to a real running backend

### 1.4 Relationship to Main Spec

The CLI client reuses `aya-protocol` (SBE codecs) directly. It implements the client side of every message type defined in [SPEC.md Section 3](SPEC.md#3-sbe-protocol-definition). Any message the mobile client can send, the CLI can send. Any response the mobile client can receive, the CLI can decode and display.

---

## 2. System Overview

```
                                 +-------------------+
                                 |   Aya Backend     |
                                 |   (running)       |
                                 +--------+----------+
                                          |
                                   HTTP + SBE
                                   WebSocket (Phase 2)
                                          |
+-------------------+            +--------v----------+
| Test Scripts /    |  Java API  |   aya-cli         |
| Cucumber Steps    +----------->|                   |
| (automated)       |            |  - Key Manager    |
+-------------------+            |  - SBE Codec      |
                                 |  - HTTP Client    |
+-------------------+            |  - WS Client      |
| Developer         |  stdin/    |  - REPL Engine    |
| (manual testing)  +--stdout--->|  - Portfolio Sim  |
+-------------------+            |  - Response Renderer|
                                 +-------------------+
```

---

## 3. Module Structure

The CLI client lives in the existing Aya project as a new module:

```
aya-backend/
  aya-cli/
    src/main/java/aya/cli/
      AyaCli.java              # Entry point, arg parsing
      repl/
        ReplEngine.java        # Interactive REPL loop
        CommandParser.java     # Parses REPL commands
      client/
        AyaHttpClient.java     # HTTP transport, SBE encode/decode
        AyaWsClient.java       # WebSocket transport (Phase 2)
        RequestBuilder.java    # Fluent builder for AssistantRequest
        ResponseParser.java    # Decode AssistantResponse, extract payloads
      keys/
        KeyManager.java        # Generate, load, save ECDSA key pairs
        RequestSigner.java     # Sign SBE payloads
      portfolio/
        PortfolioSimulator.java  # Configurable fake portfolios
        PortfolioProfile.java    # Named portfolio profiles (e.g., "whale", "beginner")
      render/
        ResponseRenderer.java  # Pretty-print SBE responses to terminal
        TableFormatter.java    # Format market data, portfolios as tables
        TxRenderer.java        # Render TransactionBundle details
      script/
        ScriptRunner.java      # Execute .aya script files
        ScriptParser.java      # Parse script commands
      harness/
        TestHarness.java       # Java API for integration/BDD tests
        AssertionHelpers.java  # SBE response assertion utilities
    src/main/resources/
      portfolios/
        default.yml            # Default test portfolio
        whale.yml              # High-balance portfolio
        empty.yml              # Empty portfolio
        multichain.yml         # Assets across all chains
    src/test/java/aya/cli/
      ...                      # Unit tests for the CLI itself
```

### Dependencies

| Dependency | Purpose |
|-----------|---------|
| `aya-protocol` | SBE codecs (generated encoders/decoders) |
| Java HTTP Client (`java.net.http`) | HTTP transport (built-in, no extra deps) |
| Java WebSocket Client | WebSocket transport (built-in since JDK 11) |
| Bouncy Castle | ECDSA secp256k1 key generation and signing |
| picocli | Command-line argument parsing |
| JLine 3 | REPL line editing, history, tab completion |

No external HTTP libraries — the JDK's built-in `HttpClient` is sufficient and keeps the dependency footprint minimal.

---

## 4. Key Management

### 4.1 Key Generation

```bash
aya-cli keys generate
# Generates a new secp256k1 key pair
# Saves to ~/.aya-cli/keys/default.pem (or specified path)
# Prints the public key (hex-encoded)
```

### 4.2 Key Storage

Keys are stored in `~/.aya-cli/keys/` as PEM files:
- `default.pem` — the default key pair
- Named keys: `alice.pem`, `bob.pem`, etc. for multi-user testing

### 4.3 Key Loading

```bash
aya-cli --key alice       # Use the key named "alice"
aya-cli --key ./mykey.pem # Use a key file by path
```

### 4.4 Request Signing

Every request is signed with the active key, matching the mobile app's behavior:

1. Build the SBE payload (without signature field)
2. Sign the payload bytes with ECDSA secp256k1
3. Attach the public key and signature to the `AssistantRequest` envelope

The `RequestSigner` uses Bouncy Castle for signing (same curve as Ethereum and Bitcoin wallets).

---

## 5. SBE Protocol Client

### 5.1 Encoding

The CLI reuses the generated codecs from `aya-protocol`:

```java
// Build a UserMessage
UserMessageEncoder encoder = new UserMessageEncoder();
encoder.wrapAndApplyHeader(buffer, 0, messageHeaderEncoder)
    .text("What's the price of ETH?")
    .preferredChain(ChainId.ETHEREUM);

// Wrap in AssistantRequest
AssistantRequestEncoder request = new AssistantRequestEncoder();
request.wrapAndApplyHeader(buffer, 0, messageHeaderEncoder)
    .schemaVersion(1)
    .requestId(nextRequestId())
    .timestamp(System.currentTimeMillis())
    .messageType(MessageType.USER_MESSAGE)
    .sessionId(currentSessionId)
    .publicKey(activePublicKey)
    .signature(sign(payloadBytes))
    .payload(userMessageBytes);
```

### 5.2 Decoding

```java
// Decode AssistantResponse
AssistantResponseDecoder response = new AssistantResponseDecoder();
response.wrapAndApplyHeader(buffer, 0, messageHeaderDecoder);

switch (response.responseType()) {
    case TEXT -> decodeTextResponse(response.payload());
    case TRANSACTION_BUNDLE -> decodeTransactionBundle(response.payload());
    case CLIENT_ACTION -> decodeClientAction(response.payload());
    case MARKET_DATA -> decodeMarketData(response.payload());
    case ERROR -> decodeError(response.payload());
    // ... etc
}
```

### 5.3 Schema Version

The CLI sends the same `schemaVersion` as the backend supports. If the backend is at a newer version, the CLI handles unknown fields gracefully (per SBE versioning rules).

---

## 6. HTTP Transport

### 6.1 Request Flow

```java
public class AyaHttpClient {
    private final HttpClient httpClient;
    private final String baseUrl;
    private final KeyManager keyManager;

    public AssistantResponse send(String text, PortfolioProfile portfolio) {
        byte[] sbePayload = buildRequest(text, portfolio);
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + "/assistant"))
            .header("Content-Type", "application/x-sbe")
            .POST(HttpRequest.BodyPublishers.ofByteArray(sbePayload))
            .timeout(Duration.ofSeconds(30))
            .build();

        HttpResponse<byte[]> response = httpClient.send(request,
            HttpResponse.BodyHandlers.ofByteArray());

        return decodeResponse(response.body());
    }
}
```

### 6.2 Endpoint

| Method | Path | Content-Type | Body |
|--------|------|-------------|------|
| POST | `/assistant` | `application/x-sbe` | SBE-encoded `AssistantRequest` |

Response: `application/x-sbe` body containing SBE-encoded `AssistantResponse`.

### 6.3 Error Handling

| HTTP Status | Meaning | CLI Behavior |
|------------|---------|-------------|
| 200 | Success | Decode and render SBE response |
| 400 | Bad request (malformed SBE) | Show error, suggest checking encoding |
| 401 | Auth failure | Show "Invalid signature" error |
| 429 | Rate limited | Show rate limit message, wait and retry if `--retry` |
| 500 | Server error | Show "Server error", suggest retrying |
| Connection refused | Backend not running | Show "Cannot connect to {url}. Is the backend running?" |

---

## 7. WebSocket Transport (Phase 2)

### 7.1 Streaming Connection

```bash
aya-cli --stream "Analyze my portfolio and suggest a strategy"
```

1. Opens WebSocket to `ws://{host}/stream`
2. Sends SBE-encoded `AssistantRequest` as binary frame
3. Receives `StreamChunk` messages as binary frames
4. `TEXT_DELTA` chunks are printed progressively (typewriter effect)
5. `TRANSACTION_PARTIAL` / `ACTION_PARTIAL` are buffered until `isFinal=true`
6. Connection closes after the final chunk

### 7.2 Interactive Streaming

In REPL mode, streaming can be toggled:
```
aya> /stream on
Streaming enabled. Responses will appear progressively.
aya> Analyze my portfolio
Analyzing... Based on your holdings, I'd suggest... [streams progressively]
```

---

## 8. Interactive Mode (REPL)

### 8.1 Launching

```bash
aya-cli                          # Default: connect to localhost:8080
aya-cli --url http://server:8080 # Connect to specific backend
aya-cli --key alice              # Use specific key
aya-cli --portfolio whale        # Use high-balance portfolio
```

### 8.2 REPL Interface

```
Aya CLI v1.0.0
Connected to http://localhost:8080
Key: 0x04a3b2... (default)
Portfolio: default (3 assets, 2 chains)
Session: (new)

aya> What's the price of ETH?

[Aya] ETH is currently at $3,245.67 (+2.3% 24h).
      Source: CoinGecko | Fetched: 2s ago
      ---
      This is for informational purposes only and not financial advice.

aya> Swap 100 USDC for ETH on Polygon

[Aya] I'll swap 100 USDC for approximately 0.031 ETH on Polygon via Uniswap V3.
      Estimated fee: 0.004 POL
      Slippage: 0.5%
      Shall I proceed?

aya> yes

[Aya] Here's the transaction to sign:
      ┌─────────────────────────────────────────┐
      │ Transaction 1/2: Approve USDC           │
      │ To: 0x3c499...  Gas: 55,200             │
      ├─────────────────────────────────────────┤
      │ Transaction 2/2: Swap USDC → ETH        │
      │ To: 0x68b34...  Gas: 222,000            │
      ├─────────────────────────────────────────┤
      │ Total fee: ~0.004 POL                   │
      │ Simulation: PASSED                      │
      └─────────────────────────────────────────┘

      [Sign & Send simulated — TX not broadcast in CLI mode]
```

### 8.3 REPL Commands

Slash commands control the CLI itself (not sent to the backend):

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/session new` | Start a new session |
| `/session` | Show current session ID |
| `/key <name>` | Switch active key |
| `/key generate <name>` | Generate a new key pair |
| `/portfolio <name>` | Switch portfolio profile |
| `/portfolio show` | Display current portfolio |
| `/portfolio set <asset> <chain> <balance>` | Override a balance |
| `/stream on\|off` | Toggle streaming mode |
| `/raw` | Toggle raw SBE hex dump alongside rendered output |
| `/history` | Show conversation turn history |
| `/latency` | Show latency of last request |
| `/status` | Show connection status, key, portfolio, session |
| `/script <file>` | Run a script file |
| `/export <file>` | Export conversation as JSON |
| `/quit` | Exit |

### 8.4 Tab Completion

JLine provides tab completion for:
- Slash commands (`/help`, `/portfolio`, etc.)
- Portfolio profile names
- Key names
- Common crypto terms (ETH, BTC, USDC, etc.)

### 8.5 History

Command history is saved to `~/.aya-cli/history` and persists across sessions. Arrow keys navigate history.

---

## 9. Script Mode

### 9.1 Script Files

`.aya` script files allow batch testing:

```bash
aya-cli --script test_trading.aya --url http://localhost:8080
```

### 9.2 Script Syntax

```
# Comments start with #
# Configuration commands
/key default
/portfolio whale
/session new

# Send messages (any line not starting with / or #)
What's the price of BTC?

# Wait for response (implicit — each message waits for response)
# Assert on the response
/assert response.contains "BTC"
/assert response.contains "$"
/assert response.has_disclaimer

# Continue conversation
Swap 100 USDC for ETH on Polygon
/assert response.contains "confirm"

# Confirm
yes
/assert response.has_transaction_bundle
/assert response.transaction_count == 2
/assert response.simulation_passed

# Switch portfolio mid-script
/portfolio empty
Buy 1000 ETH
/assert response.contains "insufficient" OR response.contains "don't have"

# Test off-topic refusal
Write me a poem
/assert response.is_refusal

# Test polyglot
Quel est le prix de l'ETH ?
/assert response.contains "ETH"
```

### 9.3 Assertions

| Assertion | Description |
|-----------|-------------|
| `response.contains "text"` | Response text contains the string |
| `response.not_contains "text"` | Response text does not contain the string |
| `response.has_disclaimer` | Response includes a financial disclaimer |
| `response.is_refusal` | Response is an off-topic refusal |
| `response.has_transaction_bundle` | Response includes a TransactionBundle |
| `response.has_client_action` | Response includes a ClientActionRequest |
| `response.has_settings_change` | Response includes a SettingsChangeRequest |
| `response.has_market_data` | Response includes a MarketDataResponse |
| `response.has_error` | Response is an ErrorResponse |
| `response.error_category == "AUTH"` | Error category matches |
| `response.transaction_count == N` | Number of transactions in bundle |
| `response.simulation_passed` | TransactionBundle.simulationPassed is TRUE |
| `response.chain_id == "POLYGON"` | Response targets a specific chain |
| `response.latency < 1000` | Response latency under N milliseconds |
| `response.has_trading_strategy` | Response includes a TradingStrategyResponse |
| `response.confidence == "HIGH"` | Strategy confidence matches |
| `response.retryable == true` | ErrorResponse retryable flag matches |
| `response.source == "COINGECKO"` | MarketDataResponse source matches |
| `response.action_type == "SWAP"` | ClientActionRequest actionType matches |
| `response.setting_key == "defaultChain"` | SettingsChangeRequest key matches |

**Semantic assertion definitions:**
- `response.has_disclaimer`: Checks the `hasDisclaimer` field in the `AssistantResponse` SBE envelope (boolean field, not text heuristic).
- `response.is_refusal`: Checks that (a) `responseType` is `TEXT`, (b) no structured payload is present, and (c) the text contains one of: "I can only help with", "crypto and finance", "I'm not able to", "outside my area", or similar refusal patterns. This is a heuristic check — the pattern list is maintained in `AssertionHelpers.java` and should be updated as the system prompt evolves.

### 9.4 Script Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All assertions passed |
| 1 | One or more assertions failed |
| 2 | Connection error (backend unreachable) |
| 3 | Script syntax error |

---

## 10. Portfolio Simulation

### 10.1 Portfolio Profiles

YAML files in `src/main/resources/portfolios/` define test portfolios:

```yaml
name: default
entries:
  - chain: ETHEREUM
    address: "0xabc..."
    asset: ETH
    contractAddress: ""
    balance: "5.0"
  - chain: ETHEREUM
    address: "0xabc..."
    asset: USDC
    contractAddress: "0xa0b8..."
    balance: "2000.0"
  - chain: POLYGON
    address: "0xabc..."
    asset: POL
    contractAddress: ""
    balance: "500.0"
  - chain: SOLANA
    address: "7xKX..."
    asset: SOL
    contractAddress: ""
    balance: "50.0"
  - chain: BITCOIN
    address: "bc1q..."
    asset: BTC
    contractAddress: ""
    balance: "0.1"
```

### 10.2 Built-in Profiles

| Profile | Description |
|---------|-------------|
| `default` | Moderate portfolio: 5 ETH, 2000 USDC, 500 POL, 50 SOL, 0.1 BTC |
| `whale` | High balances: 100 ETH, 50000 USDC, 5 BTC, 1000 SOL |
| `empty` | No assets — tests insufficient balance scenarios |
| `multichain` | Small amounts across all supported chains |
| `evm-only` | Assets only on EVM chains |
| `solana-only` | Assets only on Solana |
| `bitcoin-only` | BTC only |

### 10.3 Dynamic Portfolio Modification

In REPL or script mode:
```
/portfolio set ETH ETHEREUM 100.0
/portfolio set USDC POLYGON 5000.0
/portfolio remove SOL SOLANA
```

Modifications persist for the current session only.

---

## 11. Response Rendering

### 11.1 Text Responses

Rendered with ANSI colors:
- **Assistant text**: White
- **Disclaimers**: Dim/gray
- **Source attribution**: Cyan
- **Errors**: Red
- **Warnings**: Yellow

### 11.2 Market Data

Rendered as a table:
```
┌────────┬───────────┬──────────┬─────────────┐
│ Symbol │ Price     │ 24h      │ Market Cap   │
├────────┼───────────┼──────────┼─────────────┤
│ BTC    │ $67,234   │ +1.2%    │ $1.32T      │
│ ETH    │ $3,245    │ +2.3%    │ $390B       │
│ SOL    │ $142.50   │ -0.8%    │ $63B        │
└────────┴───────────┴──────────┴─────────────┘
Source: CoinGecko | Fetched: 2s ago
```

### 11.3 Transaction Bundles

Rendered as a bordered card (see REPL example in Section 8.2).

### 11.4 Errors

```
[ERROR] AUTH: Invalid signature. Check your key pair.
        Retryable: NO
```

### 11.5 Raw Mode

When `/raw` is enabled, the raw SBE bytes are hex-dumped below the rendered output:

```
[RAW] Response (142 bytes):
      02 00 01 00 00 00 30 39 00 00 01 8E ...
```

---

## 12. Integration Test Harness

### 12.1 Purpose

The `TestHarness` class provides a Java API that Cucumber step definitions and JUnit integration tests use to interact with the backend over HTTP:

```java
public class TestHarness {
    private final AyaHttpClient client;
    private final AyaWsClient wsClient;  // Phase 2
    private AssistantResponse lastResponse;
    private Duration lastLatency;

    public TestHarness(String backendUrl) { ... }

    // Key management
    public void generateKey(String name) { ... }
    public void useKey(String name) { ... }

    // Portfolio
    public void usePortfolio(String profileName) { ... }
    public void setBalance(String asset, String chain, String balance) { ... }

    // Session
    public void newSession() { ... }
    public String getSessionId() { ... }

    // Send message and wait for response
    public AssistantResponse send(String message) { ... }
    public AssistantResponse send(String message, Duration timeout) { ... }

    // Streaming (Phase 2)
    public StreamingResponse sendStreaming(String message) { ... }

    // Response access
    public AssistantResponse lastResponse() { ... }
    public String lastText() { ... }
    public Duration lastLatency() { ... }

    // Assertions (return this for chaining)
    public TestHarness assertTextContains(String substring) { ... }
    public TestHarness assertTextNotContains(String substring) { ... }
    public TestHarness assertHasDisclaimer() { ... }
    public TestHarness assertIsRefusal() { ... }
    public TestHarness assertHasTransactionBundle() { ... }
    public TestHarness assertTransactionCount(int count) { ... }
    public TestHarness assertSimulationPassed() { ... }
    public TestHarness assertHasClientAction(ActionType type) { ... }
    public TestHarness assertHasSettingsChange(String key, String value) { ... }
    public TestHarness assertHasError(ErrorCategory category) { ... }
    public TestHarness assertLatencyUnder(Duration max) { ... }
    public TestHarness assertChainId(ChainId chain) { ... }

    // Missing assertions identified in audit
    public TestHarness assertHasTradingStrategy() { ... }
    public TestHarness assertConfidence(Confidence expected) { ... }
    public TestHarness assertRetryable(boolean expected) { ... }
    public TestHarness assertHasMarketData() { ... }
    public TestHarness assertMarketDataSource(MarketDataSource expected) { ... }
    public TestHarness assertTransactionField(int sequence, String field, String expected) { ... }
    public TestHarness assertClientActionParameter(String key, String expectedValue) { ... }
}
```

### 12.2 Cucumber Integration

Step definitions use the `TestHarness`:

```java
public class TradingSteps {
    private final TestHarness harness;

    @Given("the user has {int} {word} on {word}")
    public void setBalance(int amount, String asset, String chain) {
        harness.setBalance(asset, chain, String.valueOf(amount));
    }

    @When("the user says {string}")
    public void sendMessage(String message) {
        harness.send(message);
    }

    @Then("Aya returns a TransactionBundle with {int} transactions")
    public void assertTxCount(int count) {
        harness.assertHasTransactionBundle()
               .assertTransactionCount(count);
    }

    @Then("simulationPassed is TRUE")
    public void assertSimPassed() {
        harness.assertSimulationPassed();
    }
}
```

### 12.3 Test Lifecycle

Integration tests require a running backend:

```bash
# Terminal 1: Start the backend
java -jar aya-backend.jar

# Terminal 2: Run integration tests through the CLI harness
./gradlew :aya-cli:testIntegration
```

Or with Gradle's test fixtures:
```bash
# Starts backend, runs tests, stops backend
./gradlew integrationTest
```

### 12.4 All BDD Tests Through HTTP

The existing 15 Gherkin feature files in `aya-bdd/` use the `TestHarness` for their step definitions. This means **all BDD scenarios go through real HTTP to a running backend** — maximum reliability and coverage.

```
Feature files (features/*.feature)
        |
        v
Step definitions (use TestHarness)
        |
        v
TestHarness → AyaHttpClient → HTTP POST → Aya Backend
        |
        v
Assert on SBE-decoded response
```

---

## 13. Configuration

### 13.1 CLI Arguments

| Argument | Short | Default | Description |
|----------|-------|---------|-------------|
| `--url` | `-u` | `http://localhost:8080` | Backend URL |
| `--key` | `-k` | `default` | Key name or path |
| `--portfolio` | `-p` | `default` | Portfolio profile name or YAML path |
| `--session` | `-s` | (new) | Resume a specific session ID |
| `--stream` | | (off) | Enable streaming mode |
| `--raw` | | (off) | Show raw SBE hex dumps |
| `--script` | | (none) | Run a script file instead of REPL |
| `--timeout` | `-t` | `30` | Request timeout in seconds |
| `--no-color` | | (color on) | Disable ANSI colors |
| `--quiet` | `-q` | (off) | Minimal output (for scripts) |
| `--version` | `-v` | | Print version and exit |
| `--help` | `-h` | | Print help and exit |
| `--retry` | | (off) | Retry on HTTP 429 (rate limit) with backoff |
| `--fail-fast` | | (off) | In script mode, stop on first assertion failure |
| `--verbose` | | (off) | Debug logging: request/response timing, SBE field-by-field decode, signing details |

### 13.2 Configuration File

Optional `~/.aya-cli/config.yml`:

```yaml
url: http://localhost:8080
key: default
portfolio: default
stream: false
timeout: 30
color: true
```

CLI arguments override the config file.

### 13.3 Environment Variables

| Variable | Description |
|----------|-------------|
| `AYA_CLI_URL` | Backend URL |
| `AYA_CLI_KEY` | Key name or path |
| `AYA_CLI_PORTFOLIO` | Portfolio profile |

Precedence: CLI args > env vars > config file > defaults.

---

## 14. Testing Strategy

### 14.1 CLI Unit Tests (`@fast`)

Test the CLI's own logic without a running backend:

- SBE encoding correctness (encode a UserMessage, verify bytes)
- SBE decoding correctness (decode sample response bytes)
- Key generation and signing (sign payload, verify signature)
- Portfolio profile loading and parsing
- Script parser (valid and invalid scripts)
- Assertion evaluation
- REPL command parsing
- Response rendering (text, tables, transaction cards)

### 14.2 CLI Integration Tests (`@integration`)

Require a running backend:

- Send a simple message, verify response is valid SBE
- Full conversation flow (multi-turn)
- Portfolio metadata sent correctly
- Invalid signature is rejected
- Rate limiting is enforced
- Streaming response assembly (Phase 2)
- Script execution with assertions

### 14.3 BDD Integration Tests

The existing 15 feature files use `TestHarness` step definitions that go through HTTP. When running `./gradlew cucumber`, every scenario hits the real backend over HTTP. This is the primary integration test mechanism.

### 14.4 Property-Based Tests (`@property`)

- SBE round-trip: for any arbitrary `UserMessage`, `encode(decode(x)) == x`
- Key signing: for any arbitrary payload, `verify(sign(payload, privateKey), publicKey, payload) == true`
- Portfolio serialization: any valid portfolio profile round-trips through YAML

### 14.5 Build

```bash
# Build the CLI
./gradlew :aya-cli:build

# Run as JAR
java -jar aya-cli/build/libs/aya-cli.jar

# Or via Gradle run
./gradlew :aya-cli:run --args="--url http://localhost:8080"
```

---

*For the backend specification, see [SPEC.md](SPEC.md).*
*For the CLI client's behavioral expectations, see [CLI_CLIENT_BEHAVIORS_AND_EXPECTATIONS.md](CLI_CLIENT_BEHAVIORS_AND_EXPECTATIONS.md).*
*For the CLI client's architecture, see [CLI_CLIENT_ARCHITECTURE.md](CLI_CLIENT_ARCHITECTURE.md).*
