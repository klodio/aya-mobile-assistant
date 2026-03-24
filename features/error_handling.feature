@bdd
Feature: Error Handling
  As the Aya backend
  I want to handle all error conditions gracefully
  So that users always receive informative, safe, and actionable error messages

  # References: SPEC Section 13 (Error Handling)
  # B&E Section 4 (Edge Cases), Section 6.4 (Security Guardrails)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  # --- LLM Failures ---

  @phase1 @fast
  Scenario: LLM service temporarily unavailable
    Given all LLM providers are down
    When a request arrives
    Then Aya returns an ErrorResponse
    And errorCategory is LLM_FAILURE
    And retryable is TRUE
    And the message says something like "Our AI is temporarily unavailable. Please try again in a moment."

  @phase1 @fast
  Scenario: LLM returns malformed output
    Given the LLM returns output that cannot be parsed
    When processing the response
    Then the system regenerates once with the same provider
    And if it fails again, returns a generic safe response

  # --- Chain RPC Failures ---

  @phase1 @fast
  Scenario: Ethereum RPC unreachable
    Given the Ethereum RPC endpoint is unreachable
    When the user asks for a transaction on Ethereum
    Then Aya returns an ErrorResponse
    And errorCategory is CHAIN_ERROR
    And the message says "Unable to reach the Ethereum network. Please try again."
    And retryable is TRUE

  @phase1 @fast
  Scenario: RPC timeout with retry
    Given the RPC call times out on the first attempt
    When the system retries with exponential backoff
    And the retry succeeds
    Then the user receives a normal response
    And is unaware of the initial failure

  @phase2 @fast
  Scenario: RPC returns execution error
    Given the RPC returns an error during transaction simulation
    When the error is parsed
    Then a meaningful message is returned to the user
    And raw RPC error details are not exposed

  # --- Market Data Failures ---

  @phase1 @fast
  Scenario: CoinGecko API down, fallback to DeFiLlama
    Given CoinGecko API is returning errors
    And DeFiLlama is available
    When the user asks for a price
    Then Aya tries DeFiLlama as a fallback
    And the source attribution reflects DeFiLlama

  @phase1 @fast
  Scenario: All market data APIs down
    Given CoinGecko and DeFiLlama are both unavailable
    When the user asks "What's the price of BTC?"
    Then Aya returns an ErrorResponse
    And errorCategory is MARKET_DATA_ERROR
    And the message explains that market data is temporarily unavailable
    And retryable is TRUE

  # --- Transaction Simulation Failures ---

  @phase2 @fast
  Scenario: Swap simulation fails due to insufficient liquidity
    Given a swap on a low-liquidity pool
    When Aya simulates the transaction
    Then Aya tells the user about the liquidity issue
    And suggests trying a smaller amount or different protocol
    And does not present the failing transaction for signing

  @phase2 @fast
  Scenario: Simulation fails with custom Solidity error
    Given a smart contract reverts with a custom error
    When the revert reason is parsed
    Then Aya translates it into a human-readable explanation
    And does not show raw hex error data

  # --- Partial Multi-Step Failures ---

  @phase2 @fast
  Scenario: Approve succeeded but swap fails
    Given a 2-step transaction (approve + swap)
    And the user signed and confirmed the approval
    But the swap simulation now fails (price moved)
    Then Aya acknowledges the approval went through
    And reports the swap failure
    And explains: "Your USDC approval is confirmed, but the swap failed due to price movement. You can try again with updated parameters."
    And offers to rebuild the swap with a fresh quote

  @phase2 @fast
  Scenario: Bridge source confirmed, destination pending
    Given the user bridged assets from Ethereum to Arbitrum
    And the source chain transaction is confirmed
    But the destination chain claim is not yet available
    Then Aya tracks the bridge status in the session
    And informs the user that the claim will be available later

  # --- Input Validation Errors ---

  @phase1 @fast
  Scenario: Empty user message
    When the user sends an empty or whitespace-only text message
    Then Aya returns an ErrorResponse
    And errorCategory is VALIDATION
    And the message asks the user to type a question or command

  @phase1 @fast
  Scenario: Extremely long user message
    When the user sends a message exceeding 10000 characters
    Then Aya truncates or rejects the message
    And returns an appropriate VALIDATION error

  # --- Internal Errors ---

  @phase1 @fast
  Scenario: Unexpected NullPointerException
    Given an unexpected internal error occurs
    Then the user receives a generic "Something went wrong" message
    And no stack trace or internal details are exposed
    And errorCategory is INTERNAL
    And the error is logged internally for debugging

  @phase1 @fast
  Scenario: SQLite database error
    Given the SQLite database is temporarily locked or corrupted
    When a read/write is attempted
    Then Aya handles the error gracefully
    And the user receives a generic error without database details

  # --- Timeout Handling ---

  @phase1 @fast
  Scenario: Tool execution timeout
    Given a tool execution exceeds its configured timeout (e.g., 10 seconds)
    When the timeout triggers
    Then Aya returns an error explaining the operation took too long
    And suggests trying again
    And does not hang indefinitely

  @phase1 @fast
  Scenario: Overall request timeout
    Given the total request processing exceeds 30 seconds
    When the timeout triggers
    Then Aya returns an error response
    And errorCategory is INTERNAL
    And retryable is TRUE

  # --- Unsupported Operations ---

  @phase1 @fast
  Scenario: Unsupported chain requested
    When the user asks "Bridge USDC to Fantom"
    And Fantom is not a supported chain
    Then Aya returns an informative message listing supported chains
    And does not return an error code (this is a conversational response, not a system error)

  @phase1 @fast
  Scenario: Unsupported action type
    When the user asks to perform an action not yet supported (e.g., "Create an NFT")
    Then Aya explains that the feature is not yet available
    And suggests available alternatives

  # --- Missing ErrorCategory Assertions ---

  @phase2 @fast
  Scenario: Transaction simulation failure returns TX_SIMULATION_FAILED
    Given a swap transaction that will revert
    When Aya simulates the transaction
    Then an ErrorResponse is returned with errorCategory TX_SIMULATION_FAILED
    And the message explains the revert reason

  @phase1 @fast
  Scenario: Unsupported feature returns UNSUPPORTED
    When the user asks to perform an action not yet available (e.g., "Create an NFT")
    Then an ErrorResponse is returned with errorCategory UNSUPPORTED
    And the message explains the feature is not yet available
