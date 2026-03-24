@bdd @cli
Feature: CLI Portfolio Simulation
  As a developer testing the Aya backend
  I want to simulate different portfolio states
  So that I can test balance-dependent behaviors like trading and strategy advice

  # References: CLI_CLIENT_SPEC Section 10 (Portfolio Simulation)
  # CLI B&E Section 2.7 (Portfolio Simulation)

  Background:
    Given the Aya backend is running
    And the CLI is connected

  @phase1 @fast
  Scenario: Load default portfolio profile
    When the CLI starts with --portfolio default
    Then the active portfolio has entries for ETH, USDC, POL, SOL, and BTC

  @phase1 @fast
  Scenario: Load whale portfolio profile
    When the user runs /portfolio whale
    Then the active portfolio has high balances
    And subsequent messages include the whale portfolio metadata

  @phase1 @fast
  Scenario: Load empty portfolio profile
    When the user runs /portfolio empty
    Then the active portfolio has no entries
    And any trade request results in an insufficient balance response

  @phase1 @fast
  Scenario: Dynamic balance override
    Given the default portfolio is active
    When the user runs /portfolio set ETH ETHEREUM 100.0
    Then the ETH balance on Ethereum is 100.0
    And all other balances remain unchanged

  @phase1 @fast
  Scenario: Remove an asset from portfolio
    Given the default portfolio is active
    When the user runs /portfolio remove SOL SOLANA
    Then SOL on Solana is no longer in the portfolio

  @phase1 @fast
  Scenario: Display current portfolio
    Given the default portfolio is active
    When the user runs /portfolio show
    Then a table is displayed with chain, asset, and balance columns

  @phase1 @fast
  Scenario: Custom portfolio JSON file
    Given a custom portfolio file at /tmp/test_portfolio.json
    When the CLI starts with --portfolio /tmp/test_portfolio.json
    Then the custom portfolio is loaded

  @phase1 @fast
  Scenario: Invalid portfolio JSON
    Given a malformed portfolio JSON file
    When the CLI tries to load it
    Then an error message describes the JSON parsing issue
    And the CLI does not crash

  @phase1 @fast
  Scenario: Portfolio modifications do not persist across sessions
    Given the user overrides ETH balance to 999.0
    When the CLI restarts
    Then the ETH balance is back to the profile default

  @phase1 @fast
  Scenario Outline: Built-in portfolio profiles
    When the user runs /portfolio <profile>
    Then the portfolio is loaded successfully
    And the description matches <description>

    Examples:
      | profile      | description                      |
      | default      | Moderate multi-chain portfolio   |
      | whale        | High balances for large trades   |
      | empty        | No assets                        |
      | multichain   | Small amounts across all chains  |
      | evm-only     | Assets only on EVM chains        |
      | solana-only  | Assets only on Solana            |
      | bitcoin-only | BTC only                         |
