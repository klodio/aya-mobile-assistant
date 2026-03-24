@bdd
Feature: Conversational Assistant
  As a user of the Aya wallet
  I want to have natural conversations with the AI assistant
  So that I can get help navigating blockchain and finance topics

  # References: SPEC Section 4 (Agent Pipeline), Section 9 (Conversation Management)
  # B&E Section 2.1 (Conversational Behaviors)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  @phase1 @fast
  Scenario: Basic greeting and introduction
    Given a new session
    When the user sends "Hello"
    Then Aya responds with an introduction of its capabilities
    And the response mentions blockchain, trading, and portfolio topics
    And the response includes a financial disclaimer

  @phase1 @fast
  Scenario: Multi-turn context retention
    Given a conversation where the user asked "What is the price of ETH?"
    And Aya responded with the current ETH price
    When the user sends "And what about its market cap?"
    Then Aya responds with ETH market cap
    And the response does not ask which asset the user means

  @phase1 @fast
  Scenario: Session persistence with sessionId
    Given a session with id "550e8400-e29b-41d4-a716-446655440000"
    And the user previously asked about Bitcoin
    When the user sends a new message with sessionId "550e8400-e29b-41d4-a716-446655440000"
    And the message is "How about its dominance?"
    Then Aya responds with Bitcoin dominance information
    And the conversation history includes the previous Bitcoin discussion

  @phase1 @fast
  Scenario: Clarification on vague messages with no context
    Given a new session
    When the user sends "Tell me about it"
    Then Aya asks what topic the user is referring to
    And the response suggests example crypto/finance topics

  @phase1 @fast
  Scenario: Clarification on ambiguous short messages
    Given a new session
    When the user sends "Buy"
    Then Aya asks what asset the user wants to buy
    And the response asks for the amount and optionally the chain

  @phase1 @fast
  Scenario: Follow-up after completed action
    Given a conversation where the user swapped 100 USDC for ETH
    When the user asks "How much did I spend in fees?"
    Then Aya recalls the swap details from the conversation
    And provides the fee information from the previous transaction

  @phase1 @fast
  Scenario: Default chain inference from settings
    Given the user's preferred chain is set to Polygon
    And a new session
    When the user sends "What's my USDC balance?"
    Then Aya checks the user's USDC balance on Polygon
    And mentions Polygon in the response

  @phase1 @fast
  Scenario: Context maintained across multiple topics
    Given the user asked about ETH price
    And then asked about SOL staking
    When the user sends "Go back to the first thing we talked about"
    Then Aya returns to discussing ETH
    Or asks for clarification if the reference is ambiguous

  @phase1
  Scenario: Long conversation with context summarization
    Given a conversation with more than 20 turns
    When the user references something from the first turn
    Then Aya either recalls it from the context summary
    Or asks for clarification if the summary doesn't contain the detail

  @phase1 @fast
  Scenario: New session creation when no sessionId provided
    Given no sessionId is provided in the request
    When the user sends "Hello"
    Then a new sessionId is generated
    And the response envelope contains the new sessionId

  @phase1 @fast
  Scenario: Session bound to public key
    Given a session created by public key "0xABC"
    When a request arrives for that session from public key "0xDEF"
    Then the request is rejected with an AUTH error

  @phase1 @fast
  Scenario: Session expiry after inactivity
    Given a session that has been inactive for more than 24 hours
    When the user sends a message with that sessionId
    Then a new session is created
    And the old conversation history is not loaded

  # --- Polyglot Support ---

  @phase1 @fast
  Scenario: Respond in user's language - French
    When the user sends "Quel est le prix du Bitcoin ?"
    Then Aya responds in French
    And the response includes the BTC price
    And the disclaimer is in French

  @phase1 @fast
  Scenario: Respond in user's language - Japanese
    When the user sends "ETHの価格は？"
    Then Aya responds in Japanese
    And the response includes the ETH price

  @phase1 @fast
  Scenario: Respond in user's language - Spanish
    When the user sends "Quiero comprar SOL"
    Then Aya responds in Spanish
    And follows the normal trading flow (ask amount, confirm, etc.)

  @phase1 @fast
  Scenario: Language consistency in multi-turn
    Given the user has been writing in Portuguese
    When the user sends a follow-up message in Portuguese
    Then Aya continues responding in Portuguese
