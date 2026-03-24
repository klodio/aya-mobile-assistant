@bdd @performance
Feature: Performance Targets
  As the Aya backend
  I must meet latency and throughput targets
  So that the user experience feels responsive

  # References: SPEC Section 14 (Performance), B&E Section 5 (Performance Expectations)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  @phase1 @performance
  Scenario: Simple price query latency
    When the user asks "What's the price of BTC?"
    Then the response arrives within 1500 milliseconds (P95 target)

  @phase1 @performance
  Scenario: Settings command latency
    When the user says "Set my default chain to Polygon"
    Then the response arrives within 1000 milliseconds

  @phase1 @performance
  Scenario: Off-topic refusal latency
    When the user says "Write me a poem"
    Then the response arrives within 800 milliseconds

  @phase2 @performance
  Scenario: Transaction building latency
    Given the user has 100 USDC on Ethereum
    When the user confirms a swap of 100 USDC for ETH
    Then the TransactionBundle response arrives within 6000 milliseconds (P95 target)

  @phase2 @performance
  Scenario: Streaming first token latency
    Given streaming mode is enabled
    When the user asks a question
    Then the first StreamChunk arrives within 800 milliseconds (P95 target)

  @phase1 @performance
  Scenario: Model tier selection is sub-millisecond
    When any user message is received
    Then the model tier selection decision takes less than 10 milliseconds

  @phase1 @performance
  Scenario: Sustained throughput
    Given 50 concurrent users sending requests
    When measured over 60 seconds
    Then the backend sustains at least 50 requests per second

  @phase1 @performance
  Scenario: SBE codec throughput
    When encoding and decoding 10000 AssistantRequest messages
    Then the operation completes in under 1 second (>10K ops/sec)
