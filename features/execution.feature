@bdd
Feature: Execution Flow
  As a user of the Aya wallet
  I want a clear and safe execution flow for all blockchain actions
  So that I understand what I'm signing and can confirm or reject

  # References: SPEC Section 10 (Execution Model)
  # B&E Section 2.3 (Trading), Section 6.2 (Execution Guardrails)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  # --- Client-Side Execution (Phase 1) ---

  @phase1 @fast
  Scenario: Client-side swap execution flow
    Given the system is in Phase 1
    And the user has 100 USDC on Ethereum
    When the user confirms a swap of 100 USDC for ETH
    Then Aya returns a ClientActionRequest
    And actionType is SWAP
    And parameters include:
      | key       | present |
      | fromToken | yes     |
      | toToken   | yes     |
      | amount    | yes     |
      | chainId   | yes     |
    And explanationText describes the swap in natural language
    And confirmationRequired is TRUE

  @phase1 @fast
  Scenario: Client-side bridge execution flow
    Given the system is in Phase 1
    When the user confirms bridging 50 USDC from Ethereum to Arbitrum
    Then Aya returns a ClientActionRequest
    And actionType is BRIDGE
    And parameters include fromChain, toChain, token, and amount

  @phase1 @fast
  Scenario: Settings change execution flow
    When the user confirms changing default chain to Polygon
    Then Aya returns a ClientActionRequest
    And actionType is SETTINGS_CHANGE
    And parameters include key and value
    And this flow is used in all phases (settings are always client-side)

  # --- Server-Generated Transaction (Phase 2+) ---

  @phase2 @fast
  Scenario: Server-generated swap execution flow
    Given the system is in Phase 2
    And the user has 100 USDC on Ethereum
    When the user confirms a swap of 100 USDC for ETH
    Then Aya returns a TransactionBundle
    And each transaction has:
      | field       | present |
      | sequence    | yes     |
      | to          | yes     |
      | data        | yes     |
      | value       | yes     |
      | gasLimit    | yes     |
      | description | yes     |
    And simulationPassed is TRUE
    And totalEstimatedFee is present and non-zero

  @phase2 @fast
  Scenario: Server-generated Bitcoin PSBT execution flow
    Given the user has 0.5 BTC
    When the user confirms sending 0.1 BTC
    Then Aya returns a TransactionBundle
    And chainId is BITCOIN
    And the single transaction's data contains a base64-encoded PSBT

  # --- Confirmation Flow ---

  @phase1 @fast
  Scenario: Explicit confirmation required before execution
    When Aya presents any action (trade, stake, bridge, transfer)
    Then the user must explicitly say "yes", "confirm", or equivalent
    And saying "no" or "cancel" cancels the action
    And Aya never auto-executes

  @phase1 @fast
  Scenario: Confirmation with "yes"
    Given Aya presented a swap and is awaiting confirmation
    When the user says "Yes"
    Then the action proceeds to execution

  @phase1 @fast
  Scenario: Confirmation with "go ahead"
    Given Aya presented a swap and is awaiting confirmation
    When the user says "Go ahead"
    Then the action proceeds to execution

  @phase1 @fast
  Scenario: Rejection with "no"
    Given Aya presented a swap and is awaiting confirmation
    When the user says "No"
    Then the pending action is cancelled
    And Aya acknowledges the cancellation

  @phase1 @fast
  Scenario: Rejection with "cancel"
    Given Aya presented a swap and is awaiting confirmation
    When the user says "Cancel that"
    Then the pending action is cancelled

  @phase1 @fast
  Scenario: New message while awaiting confirmation (implicit cancel)
    Given Aya is awaiting confirmation for a swap
    When the user says "Actually, what's the price of SOL?"
    Then the pending swap is implicitly cancelled
    And Aya responds to the SOL price query

  # --- Multi-Transaction Sequencing ---

  @phase2 @fast
  Scenario: Multiple transactions presented in order
    Given a TransactionBundle with 3 sequential transactions
    Then they are numbered with sequence 1, 2, and 3
    And the description for each explains what it does
    And the client must execute them in sequence order

  @phase2 @fast
  Scenario: Approve + swap presented clearly
    Given a TransactionBundle with approve (sequence 1) and swap (sequence 2)
    Then the descriptions clearly explain:
      | sequence | description_contains |
      | 1        | Approve              |
      | 2        | Swap                 |
    And the user understands they need to sign both

  # --- Fee Display ---

  @phase2 @fast
  Scenario: Total fee displayed before confirmation
    When Aya presents a TransactionBundle for confirmation
    Then the totalEstimatedFee is included in the response text
    And the fee is in the chain's native token (e.g., ETH for Ethereum, SOL for Solana)

  @phase2 @fast
  Scenario: Individual transaction fees
    Given a TransactionBundle with 2 transactions
    Then each transaction's description includes its estimated gas cost

  # --- Execution Failure Recovery ---

  @phase1 @fast
  Scenario: User reports transaction failure
    Given the user signed and broadcast a transaction
    And it failed on-chain
    When the user sends a TransactionStatus with status FAILED
    Then Aya analyzes the failure
    And provides a human-readable explanation
    And suggests alternatives or next steps

  @phase2 @fast
  Scenario: Transaction confirmed successfully
    Given the user signed and broadcast a transaction
    When the user sends a TransactionStatus with status CONFIRMED and blockNumber
    Then Aya acknowledges the successful transaction
    And updates the conversation context

  # --- Phase Transition ---

  @phase1 @fast
  Scenario: Phase 1 always uses ClientActionRequest for trades
    Given the system is configured for Phase 1
    When any trade is executed
    Then a ClientActionRequest is returned, not a TransactionBundle

  @phase2 @fast
  Scenario: Phase 2 uses TransactionBundle for trades
    Given the system is configured for Phase 2
    When any trade is executed
    Then a TransactionBundle is returned, not a ClientActionRequest

  @phase2 @fast
  Scenario: Settings always use ClientActionRequest regardless of phase
    Given the system is in Phase 2 or Phase 3
    When a settings change is requested
    Then a ClientActionRequest with actionType SETTINGS_CHANGE is returned
    And TransactionBundle is never used for settings
