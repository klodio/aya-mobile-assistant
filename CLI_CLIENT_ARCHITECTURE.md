# Aya CLI Test Client — Architecture

**Version**: 1.0.0-draft
**Status**: Draft
**Last Updated**: 2026-03-24
**Parent**: [CLI_CLIENT_SPEC.md](CLI_CLIENT_SPEC.md)

---

## 1. System Context

```mermaid
C4Context
    title Aya CLI Test Client — System Context

    Person(dev, "Developer", "Tests the backend manually or via scripts")
    Person(ci, "CI Pipeline", "Runs automated integration + BDD tests")

    System(cli, "aya-cli", "Java CLI client that communicates with the backend over HTTP+SBE")
    System(backend, "Aya Backend", "The system under test")

    Rel(dev, cli, "Interactive REPL")
    Rel(ci, cli, "TestHarness API / Script mode")
    Rel(cli, backend, "HTTP + SBE / WebSocket")
```

## 2. Component Diagram

```mermaid
graph TB
    subgraph "aya-cli"
        ENTRY[AyaCli.java<br/>Entry point + picocli]

        subgraph "User Interface"
            REPL[REPL Engine<br/>JLine interactive loop]
            SCRIPT[Script Runner<br/>Batch .aya file execution]
            RENDER[Response Renderer<br/>ANSI colored output]
        end

        subgraph "Protocol Layer"
            BUILDER[Request Builder<br/>Fluent API → SBE encoding]
            PARSER[Response Parser<br/>SBE decoding → typed objects]
            CODEC[aya-protocol<br/>Generated SBE codecs]
        end

        subgraph "Transport Layer"
            HTTP[HTTP Client<br/>java.net.http]
            WS[WebSocket Client<br/>Phase 2 streaming]
        end

        subgraph "Security"
            KEYMGR[Key Manager<br/>Generate/load/save keys]
            SIGNER[Request Signer<br/>ECDSA secp256k1]
        end

        subgraph "Test Support"
            PORTFOLIO[Portfolio Simulator<br/>YAML profiles + overrides]
            HARNESS[Test Harness<br/>Java API for Cucumber/JUnit]
            ASSERT[Assertion Helpers<br/>Fluent response assertions]
        end
    end

    ENTRY --> REPL
    ENTRY --> SCRIPT
    REPL --> BUILDER
    SCRIPT --> BUILDER
    HARNESS --> BUILDER
    BUILDER --> SIGNER
    BUILDER --> CODEC
    SIGNER --> KEYMGR
    BUILDER --> PORTFOLIO
    BUILDER --> HTTP
    BUILDER --> WS
    HTTP --> BACKEND[Aya Backend]
    WS --> BACKEND
    HTTP --> PARSER
    PARSER --> CODEC
    PARSER --> RENDER
    PARSER --> ASSERT
    HARNESS --> ASSERT
    SCRIPT --> ASSERT
```

## 3. Module Dependencies

```mermaid
graph LR
    PROTO[aya-protocol<br/>SBE codecs] --> CLI[aya-cli]
    CLI --> BDD[aya-bdd<br/>Step definitions use TestHarness]

    style PROTO fill:#e1f5fe
    style CLI fill:#fff3e0
    style BDD fill:#e8f5e9
```

The CLI depends only on `aya-protocol` (for SBE codecs). The BDD module depends on the CLI (for `TestHarness`). The CLI has zero dependency on server-side code.

## 4. Data Flow — Interactive Message

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant REPL as REPL Engine
    participant Builder as Request Builder
    participant Signer as Request Signer
    participant HTTP as HTTP Client
    participant Backend as Aya Backend
    participant Parser as Response Parser
    participant Render as Renderer

    Dev->>REPL: "What's the price of ETH?"
    REPL->>Builder: build(text, portfolio, sessionId)
    Builder->>Builder: Encode UserMessage as SBE
    Builder->>Builder: Wrap in AssistantRequest envelope
    Builder->>Signer: sign(payloadBytes, privateKey)
    Signer-->>Builder: signature
    Builder->>Builder: Attach publicKey + signature
    Builder->>HTTP: POST /assistant (SBE binary)
    HTTP->>Backend: HTTP request
    Backend-->>HTTP: HTTP response (SBE binary)
    HTTP->>Parser: response bytes
    Parser->>Parser: Decode AssistantResponse
    Parser->>Parser: Extract payload by responseType
    Parser->>Render: typed response object
    Render->>Dev: Formatted colored output
```

## 5. Data Flow — Integration Test

```mermaid
sequenceDiagram
    participant Cucumber as Cucumber Step
    participant Harness as TestHarness
    participant HTTP as AyaHttpClient
    participant Backend as Aya Backend

    Cucumber->>Harness: harness.setBalance("ETH", "ETHEREUM", "5.0")
    Cucumber->>Harness: harness.send("Swap 1 ETH for USDC")
    Harness->>HTTP: POST /assistant (SBE)
    HTTP->>Backend: HTTP request
    Backend-->>HTTP: HTTP response (SBE)
    HTTP-->>Harness: AssistantResponse
    Harness->>Harness: Store lastResponse, lastLatency
    Cucumber->>Harness: harness.assertTextContains("swap")
    Cucumber->>Harness: harness.assertHasDisclaimer()
    Harness->>Harness: Assert passes
```

## 6. Data Flow — Script Execution

```mermaid
sequenceDiagram
    participant Runner as Script Runner
    participant Parser as Script Parser
    participant Client as AyaHttpClient
    participant Backend as Aya Backend

    Runner->>Parser: Parse test_trading.aya
    Parser-->>Runner: List of commands

    loop For each command
        alt Slash command
            Runner->>Runner: Execute internally (/portfolio, /key, etc.)
        else Message
            Runner->>Client: send(message)
            Client->>Backend: HTTP POST (SBE)
            Backend-->>Client: Response (SBE)
            Client-->>Runner: AssistantResponse
        else Assertion
            Runner->>Runner: Evaluate assertion against lastResponse
            alt Assertion fails
                Runner->>Runner: Record failure, continue or abort
            end
        end
    end

    Runner->>Runner: Exit with code 0 (all pass) or 1 (failures)
```

## 7. Key Management Architecture

```
~/.aya-cli/
  keys/
    default.pem     # Default key pair (auto-generated on first run)
    alice.pem       # Named key for multi-user testing
    bob.pem
  config.yml        # Optional CLI configuration
  history           # REPL command history
```

Key pairs are ECDSA secp256k1 (same curve as Ethereum wallets). PEM format for portability. The CLI never accesses real wallet keys — it generates test-only keys.

## 8. Deployment

The CLI is a single fat JAR:

```bash
./gradlew :aya-cli:shadowJar
# Produces: aya-cli/build/libs/aya-cli.jar

java -jar aya-cli.jar                    # Interactive REPL
java -jar aya-cli.jar --script test.aya  # Batch mode
```

No installation beyond JDK 21+. No external dependencies at runtime.

---

*For the full CLI specification, see [CLI_CLIENT_SPEC.md](CLI_CLIENT_SPEC.md).*
*For behavioral expectations, see [CLI_CLIENT_BEHAVIORS_AND_EXPECTATIONS.md](CLI_CLIENT_BEHAVIORS_AND_EXPECTATIONS.md).*
