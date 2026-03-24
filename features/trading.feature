@bdd
Feature: Trading
  As a user of the Aya wallet
  I want to buy, sell, and swap crypto assets using natural language
  So that I can trade without navigating complex DeFi UIs

  # References: SPEC Section 7 (Transaction Builder), Section 10 (Execution Model)
  # B&E Section 2.3 (Trading & Execution)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  @phase1 @fast
  Scenario: Simple swap request with explicit parameters
    Given the user has 500 USDC on Ethereum in their portfolio
    When the user says "Swap 100 USDC for ETH"
    Then Aya presents the swap details including:
      | field              | present |
      | venue              | yes     |
      | estimated output   | yes     |
      | estimated fee      | yes     |
      | slippage tolerance | yes     |
    And Aya waits for user confirmation before building a transaction

  @phase1 @fast
  Scenario: Swap with explicit chain
    Given the user has 200 USDC on Polygon
    When the user says "Buy ETH with 50 USDC on Polygon"
    Then Aya builds the swap on Polygon
    And the response mentions Polygon as the chain

  @phase1 @fast
  Scenario: Swap with no chain specified uses default
    Given the user's default chain is Arbitrum
    And the user has 100 USDC on Arbitrum
    When the user says "Swap USDC for ETH"
    Then Aya uses Arbitrum as the chain
    And asks for the amount if not specified

  @phase1 @fast
  Scenario: Buy request with natural language
    When the user says "Buy me some Solana"
    Then Aya asks how much SOL the user wants to buy
    And asks on which chain or venue

  @phase1 @fast
  Scenario: Sell all of an asset
    Given the user has 10 ETH on Ethereum in their portfolio
    When the user says "Sell all my ETH"
    Then Aya confirms the amount as 10 ETH
    And presents the estimated proceeds
    And waits for user confirmation

  @phase1 @fast
  Scenario: Insufficient balance for swap
    Given the user has 50 USDC on Ethereum in their portfolio
    When the user says "Swap 100 USDC for ETH"
    Then Aya informs the user they only have 50 USDC on Ethereum
    And suggests swapping the available 50 USDC instead

  @phase1 @fast
  Scenario: Transaction confirmation flow - user confirms
    Given Aya presented a swap transaction for 100 USDC to ETH
    And is awaiting confirmation
    When the user says "Yes, go ahead"
    Then Aya returns the transaction for execution

  @phase1 @fast
  Scenario: Transaction confirmation flow - user rejects
    Given Aya presented a swap transaction for 100 USDC to ETH
    And is awaiting confirmation
    When the user says "No, cancel"
    Then Aya cancels the pending transaction
    And acknowledges the cancellation
    And offers alternatives or asks what the user wants to do instead

  @phase1 @fast
  Scenario: Implicit cancellation by changing topic
    Given Aya presented a swap transaction and is awaiting confirmation
    When the user says "What's the price of BTC?"
    Then Aya cancels the pending swap implicitly
    And responds to the price query

  @phase2 @fast
  Scenario: Multi-step transaction - approve then swap
    Given the user has no USDC approval for the Uniswap router
    And the user has 100 USDC on Ethereum
    When a swap of 100 USDC for ETH is built
    Then the TransactionBundle contains 2 transactions
    And transaction 1 has sequence 1 and description containing "Approve"
    And transaction 2 has sequence 2 and description containing "Swap"

  @phase2 @fast
  Scenario: Single-step transaction when approval exists
    Given the user has sufficient USDC approval for the Uniswap router
    And the user has 100 USDC on Ethereum
    When a swap of 100 USDC for ETH is built
    Then the TransactionBundle contains 1 transaction
    And the transaction description contains "Swap"

  @phase1 @fast
  Scenario: Client-side execution in Phase 1
    Given the system is in Phase 1
    And the user has 100 USDC on Ethereum
    When the user confirms a swap of 100 USDC for ETH via Uniswap
    Then Aya returns a ClientActionRequest
    And the actionType is SWAP
    And the parameters include fromToken, toToken, and amount

  @phase2 @fast
  Scenario: Server-generated transaction in Phase 2
    Given the system is in Phase 2
    And the user has 100 USDC on Ethereum
    When the user confirms a swap of 100 USDC for ETH
    Then Aya returns a TransactionBundle with unsigned transactions
    And each transaction has to, data, value, gasLimit, and description fields
    And simulationPassed is TRUE

  @phase1 @fast
  Scenario: Swap with slippage awareness
    Given the user has 1000 USDC on Ethereum
    When the user says "Swap 1000 USDC for ETH with 1% slippage"
    Then Aya applies 1% slippage tolerance to the swap
    And the response mentions the minimum output amount

  @phase1 @fast
  Scenario: Sell request for a specific amount
    Given the user has 5 ETH on Ethereum
    When the user says "Sell 2 ETH for USDC"
    Then Aya presents a swap of 2 ETH for USDC
    And shows the estimated USDC output

  @phase1 @fast
  Scenario Outline: Trading on different chains
    Given the user has <balance> <asset> on <chain>
    When the user says "Swap <amount> <asset> for ETH on <chain>"
    Then Aya builds the swap on <chain>

    Examples:
      | chain    | asset | balance | amount |
      | Ethereum | USDC  | 500     | 100    |
      | Polygon  | USDC  | 300     | 50     |
      | Arbitrum | USDC  | 200     | 100    |
      | Base     | USDC  | 100     | 50     |

  @phase2 @fast
  Scenario: Fee display before confirmation
    When Aya presents a transaction for confirmation
    Then the response includes the totalEstimatedFee
    And the fee is denominated in the chain's native token
