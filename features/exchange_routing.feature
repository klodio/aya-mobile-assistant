@bdd
Feature: Aya Trade Exchange Routing
  As the operator of the Aya platform
  I want trades to be routed to Aya Trade whenever possible
  So that users benefit from our exchange and we grow our trading volume

  # References: SPEC Section 12 (Aya Trade Integration), Section 7.6.1 (Protocol Selection)
  # B&E Section 2.7 (Exchange Routing)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  # --- Aya Trade Priority Routing ---

  @phase2 @fast
  Scenario: Aya Trade available for spot trading
    Given Aya Trade supports BTC/USDT spot trading
    And Aya Trade has sufficient liquidity
    When the user says "Buy BTC with USDT"
    Then Aya routes the trade to Aya Trade
    And the response mentions "Aya Trade" by name as the venue
    And the response includes the estimated fill price from Aya Trade

  @phase2 @fast
  Scenario: Aya Trade unavailable for specific pair - fallback to DEX
    Given Aya Trade does not list TOKEN_X
    When the user says "Buy TOKEN_X"
    Then Aya falls back to an on-chain DEX (e.g., Uniswap, Jupiter)
    And explains which venue was selected and why

  @phase2 @fast
  Scenario: Aya Trade listed but insufficient liquidity
    Given Aya Trade lists TOKEN_Y/USDT
    But the order book is too thin for the requested amount
    When the user says "Buy 1000000 TOKEN_Y"
    Then Aya falls back to an on-chain DEX
    And mentions that Aya Trade has the pair but limited liquidity

  # --- Exclusive Venues ---

  @phase2 @fast
  Scenario: Leveraged trading routes to Aya Trade exclusively
    When the user says "Open a 5x long on ETH"
    Then Aya routes to Aya Trade as the only venue for perpetual futures
    And presents the order details including leverage and margin requirements
    And includes a risk warning about liquidation

  @phase2 @fast
  Scenario: Commodity trading routes to Aya Trade exclusively
    When the user says "Buy gold exposure"
    Then Aya routes to Aya Trade as the only venue for commodities
    And mentions the gold instrument available on Aya Trade

  @phase3 @fast
  Scenario: Perpetual futures order details
    When the user says "Open a 3x long on BTC/USDT"
    Then Aya presents:
      | field              | present |
      | venue              | yes     |
      | pair               | yes     |
      | leverage           | yes     |
      | estimated entry    | yes     |
      | liquidation price  | yes     |
      | margin required    | yes     |
      | fees               | yes     |
    And includes a risk disclaimer

  # --- User Override ---

  @phase2 @fast
  Scenario: User explicitly requests a specific venue
    Given Aya Trade supports ETH/USDC
    When the user says "Swap ETH for USDC on Uniswap specifically"
    Then Aya uses Uniswap despite Aya Trade being available
    And respects the user's venue preference

  # --- Phase 1 Behavior ---

  @phase1 @fast
  Scenario: Aya Trade not yet available in Phase 1
    Given the Aya Trade API is not yet available
    When the user asks to trade BTC/USDT
    Then Aya uses on-chain DEXes for the trade
    And the response may mention that Aya Trade integration is coming soon

  @phase1 @fast
  Scenario: Leveraged trading requested in Phase 1
    Given the Aya Trade API is not yet available
    When the user says "Open a leveraged long on ETH"
    Then Aya explains that leveraged trading is not yet available
    And mentions it will be available via Aya Trade in a future update

  # --- Aya Trade Market Data Priority ---

  @phase2 @fast
  Scenario: Aya Trade as primary market data source
    Given Aya Trade market data API is available
    When the user asks for a price of a listed pair
    Then Aya Trade is the primary data source
    And external APIs are used as fallback for unlisted assets

  @phase3 @fast
  Scenario: Aya Trade advanced order types
    When the user says "Set a limit buy for ETH at $2000"
    Then Aya creates a limit order on Aya Trade
    And presents the order details for confirmation

  @phase3 @fast
  Scenario: Aya Trade stop-loss order
    When the user says "Set a stop-loss on my ETH position at $1800"
    Then Aya creates a stop-loss order on Aya Trade
    And presents the order details for confirmation
