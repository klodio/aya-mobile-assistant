@bdd
Feature: Asset Disambiguation
  As a user of the Aya wallet
  I want the assistant to clarify ambiguous asset references
  So that I never accidentally buy or interact with the wrong token

  # References: SPEC Section 4.1 (LLM as Orchestrator), Section 9.4 (LLM-Driven Conversation Flow)
  # B&E Section 2.9 (Disambiguation), Section 3.4 (Wrong Asset Purchases)
  # NOTE: Disambiguation is handled by the LLM through natural conversation,
  # not through a special DisambiguationRequest message type or state machine.

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  @phase1 @fast
  Scenario: Same ticker on different chains
    When the user says "Buy USDC"
    And USDC exists on Ethereum, Polygon, Arbitrum, Solana, and Base
    Then Aya asks which chain the user wants to buy USDC on
    And presents the chains as numbered options

  @phase1 @fast
  Scenario: Same ticker with default chain set
    Given the user's default chain is Polygon
    When the user says "Buy USDC"
    Then Aya infers Polygon from the user's default chain
    And confirms: "I'll buy USDC on Polygon. Is that correct?"

  @phase1 @fast
  Scenario: Same ticker, different tokens
    When the user says "Buy UNI"
    And there exist multiple tokens with ticker "UNI" across chains
    Then Aya presents the most legitimate options with:
      | field            | present |
      | token name       | yes     |
      | contract address | yes     |
      | market cap       | yes     |
      | chain            | yes     |
    And waits for user selection

  @phase1 @fast
  Scenario: Scam token filtering
    When the user says "Buy PEPE"
    And there exist hundreds of tokens named PEPE
    Then Aya shows the most legitimate PEPE by market cap
    And warns about similarly named tokens with low liquidity
    And asks the user to confirm which one they mean

  @phase1 @fast
  Scenario: Disambiguation resolved by conversation context
    Given the user has been discussing Ethereum in the current session
    When the user says "Buy some USDC"
    Then Aya infers Ethereum from context
    But still confirms the chain with the user

  @phase1 @fast
  Scenario: Disambiguation via contract address
    When the user says "Buy token at 0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    Then Aya looks up the contract address
    And identifies it as Uniswap (UNI) on Ethereum
    And confirms: "This is Uniswap (UNI) on Ethereum. How much would you like to buy?"

  @phase1 @fast
  Scenario: Subsequent message resolves disambiguation
    Given Aya asked "Which USDC do you mean?" with options:
      | option | chain    |
      | 1      | Ethereum |
      | 2      | Polygon  |
      | 3      | Arbitrum |
    When the user says "The first one"
    Then Aya proceeds with USDC on Ethereum
    And clears the disambiguation state

  @phase1 @fast
  Scenario: Disambiguation resolution by name
    Given Aya asked "Which token do you mean?" with options:
      | option | name            |
      | 1      | Uniswap (UNI)   |
      | 2      | Universe (UNI)  |
    When the user says "Uniswap"
    Then Aya proceeds with the Uniswap UNI token

  @phase1 @fast
  Scenario: No matches found
    When the user says "Buy ZZZNONTOKENXXX"
    Then Aya responds that no token matching "ZZZNONTOKENXXX" was found
    And suggests checking the ticker or providing a contract address

  @phase1 @fast
  Scenario: Partial name match
    When the user says "Buy Ethereum"
    Then Aya infers the user wants ETH
    And confirms: "You'd like to buy ETH (Ethereum). How much?"

  @phase1 @fast
  Scenario: Common name confusion
    When the user says "Buy Polygon"
    And "Polygon" could refer to POL (formerly MATIC)
    Then Aya identifies the correct token
    And confirms with the user before proceeding

  @phase1 @fast
  Scenario: Disambiguation during strategy advice
    When the user asks "Should I buy MATIC?"
    And MATIC could refer to multiple tokens or the rebranded POL
    Then Aya clarifies which asset before providing strategy advice
    And does not provide advice on the wrong token

  @phase1 @fast
  Scenario Outline: Disambiguation for popular ambiguous tickers
    When the user says "Buy <ticker>"
    Then Aya identifies potential ambiguity
    And presents the most relevant options
    And waits for user clarification

    Examples:
      | ticker |
      | UNI    |
      | MATIC  |
      | PEPE   |
      | DOGE   |
