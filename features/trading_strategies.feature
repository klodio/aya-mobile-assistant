@bdd
Feature: Trading Strategies
  As a user of the Aya wallet
  I want to get trading strategy advice based on my portfolio and market data
  So that I can make better informed investment decisions

  # References: SPEC Section 8.5 (Trading Strategy Tools), Section 5 (LLM Model Routing)
  # B&E Section 2.6 (Trading Strategies)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair
    And market data APIs are available

  @phase1 @fast
  Scenario: Portfolio-based strategy request
    Given the user holds:
      | asset | chain    | balance |
      | ETH   | Ethereum | 5       |
      | BTC   | Bitcoin  | 0.5     |
      | USDC  | Ethereum | 2000    |
    When the user asks "What should I do with my portfolio?"
    Then Aya provides a portfolio analysis
    And suggests a diversification-aware strategy
    And the response uses a Tier 2 (powerful) model
    And includes a financial disclaimer
    And confidence level is included (LOW, MEDIUM, or HIGH)

  @phase1 @fast
  Scenario: Asset-specific analysis
    When the user asks "Is SOL a good buy right now?"
    Then Aya provides market trends for SOL
    And includes current price and recent performance
    And provides a hedged opinion with reasoning
    And includes a financial disclaimer

  @phase1 @fast
  Scenario: Risk-aware recommendation for leverage
    Given the user asks "Should I long ETH with 10x leverage?"
    Then Aya warns about liquidation risks with high leverage
    And recommends conservative position sizes
    And directs the user to Aya Trade for perpetual futures
    And includes a prominent risk disclaimer

  @phase1 @fast
  Scenario: Strategy with actionable steps
    Given the user has a concentrated portfolio (80% ETH)
    When the user asks "How should I rebalance?"
    Then Aya provides a strategy with numbered actionable steps
    And each step maps to a concrete action (e.g., "Sell X ETH", "Buy Y SOL")
    And the user can reference a step (e.g., "Do step 1") to execute it

  @phase1 @fast
  Scenario: Execute a strategy step
    Given Aya previously suggested a strategy with step 1 being "Swap 1 ETH for USDC"
    When the user says "Do step 1"
    Then Aya initiates a swap of 1 ETH for USDC
    And follows the normal trading confirmation flow

  @phase1 @fast
  Scenario: Disclaimer always present on strategy responses
    When the user asks any strategy-related question
    Then the response always includes a financial disclaimer
    And the disclaimer mentions "not financial advice"

  @phase1 @fast
  Scenario: Market comparison strategy
    When the user asks "Should I buy ETH or SOL right now?"
    Then Aya compares both assets' recent performance and fundamentals
    And provides a balanced analysis
    And does not definitively recommend one over the other without caveats
    And includes a disclaimer

  @phase1 @fast
  Scenario: Strategy request with no portfolio data
    Given the user does not provide portfolio metadata
    When the user asks "How should I invest $1000 in crypto?"
    Then Aya provides general allocation suggestions
    And mentions that personalized advice requires portfolio data
    And includes a disclaimer

  @phase1 @fast
  Scenario: DCA strategy suggestion
    When the user asks "Is DCA a good strategy for Bitcoin?"
    Then Aya explains Dollar Cost Averaging
    And provides pros and cons in the context of Bitcoin's volatility
    And includes a disclaimer

  @phase1 @fast
  Scenario: Staking yield strategy
    Given the user has 10 ETH on Ethereum
    When the user asks "How can I earn yield on my ETH?"
    Then Aya suggests staking options with estimated APYs
    And compares protocols (Lido, Rocket Pool, etc.)
    And mentions any risks (slashing, smart contract risk)
    And includes a disclaimer
