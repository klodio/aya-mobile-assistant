@bdd @cli
Feature: CLI Message Sending and Receiving
  As a developer testing the Aya backend
  I want to send messages and receive responses via HTTP+SBE
  So that I can verify the backend works correctly over the wire

  # References: CLI_CLIENT_SPEC Section 5 (SBE Protocol Client), Section 6 (HTTP Transport)
  # CLI B&E Section 2.2 (Message Sending), Section 2.3 (Response Rendering)

  Background:
    Given the Aya backend is running
    And the CLI is connected with a valid key

  # --- Basic Message Flow ---

  @phase1 @fast
  Scenario: Send text message and receive text response
    When the user sends "What is staking?"
    Then the CLI receives an SBE-encoded response
    And decodes it as an AssistantTextResponse
    And displays the assistant's text

  @phase1 @fast
  Scenario: Request is SBE-encoded
    When the user sends any message
    Then the HTTP request body is valid SBE binary
    And Content-Type is "application/x-sbe"

  @phase1 @fast
  Scenario: Request is signed
    When the user sends any message
    Then the AssistantRequest contains the public key
    And the signature is a valid ECDSA secp256k1 signature over the payload

  @phase1 @fast
  Scenario: Portfolio metadata is included
    Given the active portfolio has 5 ETH on Ethereum
    When the user sends "What's my balance?"
    Then the UserMessage contains portfolioEntries
    And one entry has asset "ETH", chain ETHEREUM, balance "5.0"

  # --- Session Management ---

  @phase1 @fast
  Scenario: Session continuity across messages
    When the user sends "What's the price of ETH?"
    And then sends "And SOL?"
    Then both messages use the same sessionId
    And the backend maintains conversation context

  @phase1 @fast
  Scenario: New session command
    Given a conversation is in progress
    When the user runs /session new
    And sends "Hello"
    Then the message uses a new sessionId
    And the backend treats it as a fresh conversation

  @phase1 @fast
  Scenario: Session ID displayed
    When the user runs /session
    Then the current sessionId is displayed

  # --- Response Types ---

  @phase1 @fast
  Scenario: Market data response rendered as table
    When the user sends "Show me prices for BTC, ETH, SOL"
    And the backend returns a MarketDataResponse
    Then the CLI renders a formatted table with Symbol, Price, 24h, Market Cap

  @phase2 @fast
  Scenario: Transaction bundle rendered as card
    When the user confirms a swap
    And the backend returns a TransactionBundle
    Then the CLI renders each transaction as a bordered card
    And shows sequence, description, to address, gas limit
    And shows total fee and simulation status

  @phase1 @fast
  Scenario: Error response rendered in red
    Given the CLI sends a request with an invalid signature
    When the backend returns an ErrorResponse
    Then the CLI renders the error with category and message
    And the output is colored red

  @phase1 @fast
  Scenario: Settings change response
    When the user says "Set my default chain to Polygon"
    And the backend returns a SettingsChangeRequest
    Then the CLI displays the setting key and new value

  # --- Raw Mode ---

  @phase1 @fast
  Scenario: Raw SBE hex dump
    Given raw mode is enabled via /raw
    When the user sends a message
    Then the response is rendered normally
    And the raw SBE bytes are hex-dumped below the rendered output

  # --- Latency ---

  @phase1 @fast
  Scenario: Latency measurement
    When the user sends a message
    And then runs /latency
    Then the round-trip latency in milliseconds is displayed

  # --- Error Handling ---

  @phase1 @fast
  Scenario: Request timeout
    Given the backend takes more than 30 seconds to respond
    When the user sends a message
    Then the CLI displays a timeout error
    And does not hang indefinitely

  @phase1 @fast
  Scenario: Connection dropped mid-conversation
    Given a conversation is in progress
    And the backend goes down
    When the user sends a message
    Then the CLI displays a connection error
    And suggests checking if the backend is running
