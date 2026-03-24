@bdd @cli @phase2
Feature: CLI WebSocket Streaming
  As a developer testing streaming responses
  I want the CLI to connect via WebSocket and render streaming chunks
  So that I can verify the Phase 2 streaming protocol works correctly

  # References: CLI_CLIENT_SPEC Section 7 (WebSocket Transport)
  # CLI B&E Section 2.2 (Message Sending)

  Background:
    Given the Aya backend is running with streaming enabled
    And the CLI is connected

  @phase2 @fast
  Scenario: Streaming text response
    Given streaming mode is enabled via /stream on
    When the user sends "Tell me about Ethereum staking"
    Then the CLI connects via WebSocket
    And TEXT_DELTA chunks are displayed progressively
    And the final chunk has isFinal TRUE
    And the full text is assembled correctly

  @phase2 @fast
  Scenario: Streaming with transaction partial
    Given streaming mode is enabled
    When the user sends a message that results in a TransactionBundle
    Then TEXT_DELTA chunks are displayed progressively
    And TRANSACTION_PARTIAL chunks are buffered silently
    And the transaction card is rendered only after isFinal TRUE

  @phase2 @fast
  Scenario: Streaming error mid-response
    Given streaming mode is enabled
    And the backend encounters an error mid-stream
    When the user sends a message
    Then a final error chunk is received with isFinal TRUE
    And the error is displayed
    And the WebSocket connection closes gracefully

  @phase2 @fast
  Scenario: Toggle streaming mode
    When the user runs /stream on
    Then subsequent messages use WebSocket
    When the user runs /stream off
    Then subsequent messages use HTTP

  @phase2 @fast
  Scenario: Streaming in script mode
    Given a script file with streaming enabled:
      """
      /stream on
      /session new
      Analyze my portfolio
      /assert response.contains "portfolio"
      /assert response.has_disclaimer
      """
    When the script is executed
    Then streaming is used for the message
    And assertions work on the fully assembled response
