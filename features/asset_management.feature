@bdd
Feature: Asset Management
  As a user of the Aya wallet
  I want to stake, unstake, and bridge my assets using natural language
  So that I can manage my portfolio without complex DeFi interactions

  # References: SPEC Section 7 (Transaction Builder), Section 7.5 (Protocol Adapters)
  # B&E Section 2.4 (Asset Management)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  @phase1 @fast
  Scenario: Stake ETH
    Given the user has 10 ETH on Ethereum
    When the user says "Stake 5 ETH"
    Then Aya suggests a staking protocol (e.g., Lido)
    And shows the estimated APY
    And presents the staking action for confirmation

  @phase1 @fast
  Scenario: Stake ETH with explicit protocol
    Given the user has 10 ETH on Ethereum
    When the user says "Stake 5 ETH via Lido"
    Then Aya uses Lido specifically
    And does not suggest alternative protocols
    And shows estimated APY and staking details

  @phase2 @fast
  Scenario: Unstake SOL from Marinade
    Given the user has staked SOL via Marinade
    When the user says "Unstake my SOL from Marinade"
    Then Aya builds the Marinade unstake instruction
    And mentions any cooldown period if applicable
    And presents the transaction for confirmation

  @phase1 @fast
  Scenario: Bridge assets between chains
    Given the user has 100 USDC on Ethereum
    When the user says "Bridge 100 USDC from Ethereum to Arbitrum"
    Then Aya presents the bridge action with estimated fees and time
    And waits for user confirmation

  @phase1 @fast
  Scenario: Bridge in Phase 1 uses client-side execution
    Given the system is in Phase 1
    And the user has 100 USDC on Ethereum
    When the user confirms bridging 100 USDC to Arbitrum
    Then Aya returns a ClientActionRequest with actionType BRIDGE
    And parameters include fromChain, toChain, token, and amount

  @phase2 @fast
  Scenario: Bridge in Phase 2 uses server-generated transaction
    Given the system is in Phase 2
    And the user has 100 USDC on Ethereum
    When the user confirms bridging 100 USDC to Arbitrum
    Then Aya returns a TransactionBundle for the bridge transaction

  @phase1 @fast
  Scenario: Bridge with unsupported destination chain
    When the user says "Bridge USDC to Fantom"
    And Fantom is not a supported chain
    Then Aya informs the user that Fantom is not yet supported
    And lists the supported chains

  @phase1 @fast
  Scenario: Stake without specifying protocol
    Given the user has 5 SOL
    When the user says "Stake my SOL"
    Then Aya suggests available staking protocols for SOL (e.g., Marinade)
    And shows estimated APY for each option
    And asks the user to choose

  @phase1 @fast
  Scenario: View staking positions
    Given the user has staked assets in their portfolio metadata
    When the user asks "What do I have staked?"
    Then Aya analyzes the portfolio metadata for staked assets
    And lists each staking position with protocol, amount, and estimated rewards

  @phase1 @fast
  Scenario: Stake with insufficient balance
    Given the user has 1 ETH on Ethereum
    When the user says "Stake 5 ETH"
    Then Aya informs the user they only have 1 ETH
    And suggests staking the available 1 ETH instead

  @phase2 @fast
  Scenario: Multi-step unstake with cooldown
    Given the user has staked ETH
    When the user says "Unstake my ETH"
    Then Aya explains the unstake process including any cooldown period
    And builds the unstake request transaction
    And notes that a separate claim transaction will be needed after cooldown

  @phase1 @fast
  Scenario: Transfer assets between wallets
    Given the user has 1 ETH on Ethereum
    When the user says "Send 0.5 ETH to 0x742d35Cc6634C0532925a3b844Bc9e7595f2bD18"
    Then Aya presents the transfer details including the destination address
    And shows the estimated fee
    And waits for confirmation

  @phase1 @fast
  Scenario Outline: Staking on different chains
    Given the user has <amount> <asset> on <chain>
    When the user says "Stake <amount> <asset>"
    Then Aya suggests a staking protocol for <asset> on <chain>

    Examples:
      | chain    | asset | amount |
      | Ethereum | ETH   | 5      |
      | Solana   | SOL   | 50     |
