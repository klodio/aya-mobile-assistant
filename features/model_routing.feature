@bdd
Feature: LLM Model Routing
  As the Aya backend
  I want to route requests to the appropriate LLM model tier
  So that simple queries are fast and complex queries get powerful reasoning

  # References: SPEC Section 5 (LLM Model Routing Strategy)
  # B&E Section 2.10 (Speed & Model Routing)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair
    And at least one LLM provider per tier is available

  # --- Tier 1 (Fast) Routing ---

  # NOTE: There is no separate intent classification step. The LLM handles intent
  # natively through tool calling. Model tier selection is a simple keyword heuristic,
  # not an LLM call.

  @phase1 @fast
  Scenario: Simple price query uses fast model
    When the user asks "What's the price of BTC?"
    Then the request is routed to Tier 1 (fast) model
    And the LLM calls the get_price tool
    And total processing latency is under 1 second

  @phase1 @fast
  Scenario: Off-topic refusal uses fast model
    When the user sends "Write me a poem"
    Then the request is routed to Tier 1 (fast) model
    And the LLM declines via system prompt instructions
    And total processing latency is under 500 milliseconds

  @phase1 @fast
  Scenario: Settings command uses fast model
    When the user says "Set my default chain to Polygon"
    Then the request is routed to Tier 1 (fast) model
    And the LLM calls the change_setting tool

  @phase1 @fast
  Scenario: Conversational follow-up uses fast model
    Given a conversation about ETH
    When the user says "Yes, go ahead" to confirm a swap
    Then the request is routed to Tier 1 (fast) model
    And the LLM interprets the confirmation from conversation context
    And calls build_transaction

  # --- Tier 2 (Powerful) Routing ---

  @phase1 @fast
  Scenario: Strategy request uses powerful model
    When the user asks "Analyze my portfolio and suggest a rebalancing strategy"
    Then the keyword heuristic detects "analyze" and "strategy"
    And the request is routed to Tier 2 (powerful) model

  @phase1 @fast
  Scenario: Risk assessment uses powerful model
    When the user says "Should I leverage my ETH position?"
    Then the keyword heuristic detects "leverage"
    And the request is routed to Tier 2 (powerful) model

  @phase1 @fast
  Scenario: Most requests default to fast model
    When the user asks "Swap 100 USDC for ETH on Polygon"
    Then the keyword heuristic finds no strategy/analysis keywords
    And the request is routed to Tier 1 (fast) model
    And the fast model handles the multi-tool orchestration

  # --- Escalation ---

  @phase1 @fast
  Scenario: Escalation from Tier 1 to Tier 2 on low quality
    Given a Tier 1 model produces a response that is too short or generic
    When the quality heuristic detects this
    Then the request is re-processed with Tier 2 (powerful) model
    And the final response is from Tier 2

  # --- Provider Failover ---

  @phase1 @fast
  Scenario: LLM provider failover
    Given the primary LLM provider for Tier 1 is down
    When a request arrives
    Then the secondary provider for Tier 1 is used
    And the response still meets quality standards
    And the failover is transparent to the user

  @phase1 @fast
  Scenario: All providers for a tier down
    Given all LLM providers for Tier 2 are unavailable
    When a request requiring Tier 2 arrives
    Then Aya returns an ErrorResponse with errorCategory LLM_FAILURE
    And retryable is TRUE
    And the message is user-friendly

  # --- Latency Budget ---

  @phase1 @fast
  Scenario: Tier selection is instant (no LLM call)
    When any user message is received
    Then model tier selection completes within 10 milliseconds
    And no LLM call is made for classification

  @phase1 @fast
  Scenario: Model call timeout
    Given a model call exceeds its latency budget (e.g., 5 seconds for Tier 2)
    When the timeout triggers
    Then the system tries the fallback provider
    And if no fallback is available, returns a graceful error

  # --- Circuit Breaker ---

  @phase1 @fast
  Scenario: Circuit breaker activates after consecutive failures
    Given a provider has failed 5 consecutive times within 1 minute
    When the circuit breaker activates
    Then that provider is temporarily disabled for 30 seconds
    And requests route to the fallback provider during the cooldown

  @phase1 @fast
  Scenario: Circuit breaker resets after cooldown
    Given a provider's circuit breaker is active
    When 30 seconds have passed
    Then the provider is re-enabled for the next request
    And if it succeeds, normal operation resumes
