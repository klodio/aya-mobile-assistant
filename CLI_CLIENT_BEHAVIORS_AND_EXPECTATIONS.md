# Aya CLI Test Client — Behaviors and Expectations

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-24
**Parent**: [CLI_CLIENT_SPEC.md](CLI_CLIENT_SPEC.md)

---

## 1. Introduction

This document defines the behavioral contract for the Aya CLI Test Client (`aya-cli`). It covers what the CLI must do in both interactive (REPL) and automated (script/harness) modes. Every behavior maps to testable scenarios in the [CLI feature files](features/).

---

## 2. Desired Behaviors

### 2.1 Connection & Startup

#### B-2.1.1: Connect to Backend

**Trigger**: CLI starts with a valid `--url`.
**Expected**: CLI connects, verifies the backend is reachable (health check), and shows connection status.
**Rationale**: Developer should know immediately if the backend is up.

#### B-2.1.2: Backend Unreachable

**Trigger**: CLI starts but backend is not running at the specified URL.
**Expected**: Clear error message: "Cannot connect to {url}. Is the backend running?" Exit code 2 in script mode.
**Rationale**: Don't let the developer waste time typing commands into a disconnected client.

#### B-2.1.3: Auto-Generate Default Key

**Trigger**: First run, no keys exist in `~/.aya-cli/keys/`.
**Expected**: CLI generates a default secp256k1 key pair, saves it, and prints the public key.
**Rationale**: Zero-config startup. Developer shouldn't need to generate keys manually.

### 2.2 Message Sending

#### B-2.2.1: Send and Receive via HTTP+SBE

**Trigger**: User types a message in REPL or sends via `TestHarness.send()`.
**Expected**: Message is SBE-encoded, signed, sent as HTTP POST, and the SBE response is decoded and rendered.
**Rationale**: The CLI must behave exactly like the mobile client at the protocol level.

#### B-2.2.2: Session Continuity

**Trigger**: Multiple messages in the same REPL session.
**Expected**: All messages share the same `sessionId`. The backend maintains conversation context.
**Rationale**: Multi-turn conversation testing requires session persistence.

#### B-2.2.3: New Session on Command

**Trigger**: `/session new` in REPL.
**Expected**: A new `sessionId` is generated. Subsequent messages use the new session. Previous conversation context is lost.
**Rationale**: Developer needs to test fresh conversation starts.

#### B-2.2.4: Portfolio Metadata Sent

**Trigger**: Any message.
**Expected**: The active portfolio profile is included as `portfolioEntries` in the `UserMessage`.
**Rationale**: The backend uses portfolio data for balance checks, strategy advice, etc.

#### B-2.2.5: Request Signing

**Trigger**: Any message.
**Expected**: The SBE payload is signed with the active key. The public key and signature are attached to the `AssistantRequest`.
**Rationale**: The backend rejects unsigned requests. The CLI must sign exactly as the mobile app does.

### 2.3 Response Rendering

#### B-2.3.1: Text Response

**Trigger**: Backend returns an `AssistantTextResponse`.
**Expected**: Text is displayed with ANSI formatting. Disclaimers are dimmed. Source attributions are highlighted.
**Rationale**: Human-readable output for manual testing.

#### B-2.3.2: Transaction Bundle

**Trigger**: Backend returns a `TransactionBundle`.
**Expected**: Each transaction is rendered as a card showing sequence, description, target address, gas, and fee. Total fee and simulation status are shown.
**Rationale**: Developer must see exactly what the mobile would present to the user.

#### B-2.3.3: Error Response

**Trigger**: Backend returns an `ErrorResponse`.
**Expected**: Error is rendered in red with category, message, and retryable flag.
**Rationale**: Clear error visibility for debugging.

#### B-2.3.4: Market Data

**Trigger**: Backend returns a `MarketDataResponse`.
**Expected**: Assets are rendered as a formatted table with price, change, and market cap columns.
**Rationale**: Structured data should be visually structured.

#### B-2.3.5: Raw Mode

**Trigger**: `/raw` toggle is on.
**Expected**: Raw SBE bytes are hex-dumped below the rendered output.
**Rationale**: Debugging protocol-level issues requires seeing raw bytes.

### 2.4 REPL Interaction

#### B-2.4.1: Line Editing

**Trigger**: Developer types in the REPL.
**Expected**: Full line editing support: arrow keys, home/end, delete, backspace. Provided by JLine.
**Rationale**: Standard CLI ergonomics.

#### B-2.4.2: History Navigation

**Trigger**: Up/down arrow keys.
**Expected**: Navigate through previous commands. History persists across REPL sessions.
**Rationale**: Standard CLI ergonomics.

#### B-2.4.3: Tab Completion

**Trigger**: Tab key after partial input.
**Expected**: Complete slash commands and common terms.
**Rationale**: Faster interaction.

#### B-2.4.4: Latency Display

**Trigger**: `/latency` command or after each message if enabled.
**Expected**: Shows round-trip latency of the last request in milliseconds.
**Rationale**: Performance testing visibility.

### 2.5 Script Execution

#### B-2.5.1: Script Runs to Completion

**Trigger**: `aya-cli --script test.aya`.
**Expected**: Each command is executed sequentially. Messages are sent, responses received. Assertions are evaluated.
**Rationale**: Batch testing without human interaction.

#### B-2.5.2: Assertion Failure Reporting

**Trigger**: An assertion fails in a script.
**Expected**: The failing assertion, line number, expected value, and actual value are printed. Script continues (unless `--fail-fast`). Exit code 1.
**Rationale**: Clear failure reporting for CI pipelines.

#### B-2.5.3: Script Exit Codes

**Trigger**: Script completes.
**Expected**: Exit 0 (all pass), 1 (assertion failure), 2 (connection error), 3 (syntax error).
**Rationale**: CI pipelines rely on exit codes.

### 2.6 Integration Test Harness

#### B-2.6.1: TestHarness API

**Trigger**: Cucumber step definitions call `TestHarness` methods.
**Expected**: Messages go through real HTTP to the backend. Responses are real SBE-decoded objects. Assertions are chainable.
**Rationale**: Integration tests must test the real protocol path.

#### B-2.6.2: Backend BDD Tests Through HTTP

**Trigger**: Running `./gradlew cucumber` for backend feature files.
**Expected**: All backend BDD scenarios (conversation, trading, market data, etc.) send real HTTP requests to a running backend via the TestHarness. No mocking of the transport layer.
**Rationale**: Maximum reliability. If it passes in BDD, it works over the wire.

**Exception**: `aya_index.feature` and `protocol_health.feature` are offline tests that exercise the `aya-index` tool directly — they do not go through the backend or the TestHarness. They test seed management and protocol health monitoring, which are developer/CI workflows, not backend functionality.

### 2.7 Portfolio Simulation

#### B-2.7.1: Profile Loading

**Trigger**: `--portfolio whale` or `/portfolio whale`.
**Expected**: The whale portfolio profile is loaded from YAML and used in all subsequent requests.
**Rationale**: Different test scenarios need different portfolio states.

#### B-2.7.2: Dynamic Balance Override

**Trigger**: `/portfolio set ETH ETHEREUM 100.0`.
**Expected**: The ETH balance on Ethereum is overridden for this session. Other entries unchanged.
**Rationale**: Fine-grained control for specific test cases.

---

## 3. Undesired Behaviors

### 3.1 Silent Failures

**Trigger**: Connection drops or request fails.
**Expected**: Must NOT silently swallow errors. Always display the error.
**Risk**: Developer thinks the backend is working when it's not.

### 3.2 Unsigned Requests

**Trigger**: Any message.
**Expected**: Must NEVER send a request without a valid signature.
**Risk**: Backend rejects it, giving a false negative in testing.

### 3.3 Stale Session State

**Trigger**: Backend restarts mid-session.
**Expected**: CLI detects the session is gone (backend returns error) and suggests starting a new session.
**Risk**: Confusing error messages if the CLI doesn't handle session loss.

### 3.4 Portfolio Leaking Between Tests

**Trigger**: Running multiple test scenarios.
**Expected**: Portfolio modifications from one test must NOT leak into the next.
**Risk**: Test interdependence and flaky failures.

### 3.5 Hardcoded URLs

**Trigger**: Any configuration.
**Expected**: Backend URL must NEVER be hardcoded. Always configurable.
**Risk**: Tests only work on one developer's machine.

---

## 4. Edge Cases

### 4.1 Very Long Response

**Trigger**: Backend returns a very long text response (e.g., detailed strategy).
**Expected**: Response is fully rendered. No truncation unless `--quiet` mode.

### 4.2 Binary Data in Transaction

**Trigger**: TransactionBundle contains raw calldata bytes.
**Expected**: Calldata is rendered as hex in the transaction card. Not interpreted as text.

### 4.3 Rapid Sequential Messages

**Trigger**: Script sends messages without waiting for human input.
**Expected**: Each message waits for the previous response before sending the next. No race conditions.

### 4.4 Backend Timeout

**Trigger**: Backend takes longer than `--timeout` seconds.
**Expected**: CLI shows a timeout error. Does not hang indefinitely.

### 4.5 Invalid Portfolio YAML

**Trigger**: Malformed portfolio profile YAML.
**Expected**: Clear error message pointing to the JSON parsing issue. CLI does not crash.

---

## 5. Performance Expectations

| Operation | Target |
|-----------|--------|
| CLI startup time | <1 second |
| SBE encode/decode (per message) | <1 millisecond |
| Key generation | <500 milliseconds |
| Request signing | <10 milliseconds |
| Script parsing (1000 lines) | <100 milliseconds |

---

*For the full CLI specification, see [CLI_CLIENT_SPEC.md](CLI_CLIENT_SPEC.md).*
*For the architecture, see [CLI_CLIENT_ARCHITECTURE.md](CLI_CLIENT_ARCHITECTURE.md).*
