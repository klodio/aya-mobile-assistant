@bdd @cli
Feature: CLI Integration Test Harness
  As the test infrastructure for Aya
  The TestHarness must provide a reliable Java API for BDD and integration tests
  So that all tests go through real HTTP+SBE to the backend

  # References: CLI_CLIENT_SPEC Section 12 (Integration Test Harness)
  # CLI B&E Section 2.6 (Integration Test Harness)

  Background:
    Given the Aya backend is running
    And a TestHarness is initialized with the backend URL

  # --- Core Harness Functionality ---

  @phase1 @fast
  Scenario: Send message via harness and receive response
    When the harness sends "What's the price of BTC?"
    Then the harness receives a valid AssistantResponse
    And lastText() contains "BTC"
    And lastLatency() is greater than 0

  @phase1 @fast
  Scenario: Harness sends real HTTP requests
    When the harness sends any message
    Then the request goes through HTTP to the running backend
    And is SBE-encoded exactly like a mobile client request
    And is signed with a valid key

  @phase1 @fast
  Scenario: Harness portfolio configuration
    Given the harness portfolio has 1000 USDC on Ethereum
    When the harness sends "Swap 500 USDC for ETH"
    Then the backend receives the portfolio metadata
    And does not report insufficient balance

  @phase1 @fast
  Scenario: Harness with empty portfolio
    Given the harness uses the "empty" portfolio profile
    When the harness sends "Swap 100 USDC for ETH"
    Then the response mentions insufficient balance or asks about holdings

  @phase1 @fast
  Scenario: Harness session continuity
    When the harness sends "What's the price of ETH?"
    And then sends "And its market cap?"
    Then both requests use the same sessionId
    And the second response relates to ETH

  @phase1 @fast
  Scenario: Harness new session
    Given a conversation is in progress
    When the harness calls newSession()
    And sends "Hello"
    Then a new sessionId is used

  # --- Assertion Helpers ---

  @phase1 @fast
  Scenario: assertTextContains passes
    When the harness sends "What's the price of ETH?"
    Then assertTextContains("ETH") passes

  @phase1 @fast
  Scenario: assertTextContains fails
    When the harness sends "What's the price of ETH?"
    Then assertTextContains("XYZNONEXISTENT") throws an AssertionError

  @phase1 @fast
  Scenario: assertHasDisclaimer
    When the harness sends "What's the price of ETH?"
    Then assertHasDisclaimer() passes

  @phase1 @fast
  Scenario: assertIsRefusal
    When the harness sends "Write me a poem"
    Then assertIsRefusal() passes

  @phase1 @fast
  Scenario: assertHasError for invalid signature
    Given the harness uses an invalid key
    When the harness sends any message
    Then assertHasError(AUTH) passes

  @phase2 @fast
  Scenario: assertHasTransactionBundle
    Given a confirmed swap
    When the backend returns a TransactionBundle
    Then assertHasTransactionBundle() passes
    And assertTransactionCount(2) passes for approve+swap
    And assertSimulationPassed() passes

  @phase1 @fast
  Scenario: assertLatencyUnder
    When the harness sends "Hello"
    Then assertLatencyUnder(5 seconds) passes for a responsive backend

  # --- Multi-Key Testing ---

  @phase1 @fast
  Scenario: Switch keys for multi-user testing
    Given harness has keys "alice" and "bob"
    When alice sends a message in her session
    And bob sends a message in his session
    Then both sessions are independent
    And alice's session is bound to alice's public key
    And bob's session is bound to bob's public key

  @phase1 @fast
  Scenario: Cross-key session rejection
    Given alice created a session
    When bob tries to send a message in alice's session
    Then the backend rejects it with an AUTH error

  # --- BDD Integration ---

  @phase1 @fast
  Scenario: All BDD feature files use TestHarness
    Given the Cucumber step definitions use TestHarness
    When ./gradlew cucumber is executed
    Then every scenario sends real HTTP requests to the backend
    And responses are real SBE-decoded objects
    And no HTTP/SBE layer is mocked

  # --- Portfolio Isolation Between Tests ---

  @phase1 @fast
  Scenario: Portfolio does not leak between scenarios
    Given scenario A sets portfolio balance to 1000 ETH
    When scenario A completes
    And scenario B starts with default portfolio
    Then scenario B has the default portfolio (5 ETH)
    And not 1000 ETH from scenario A
