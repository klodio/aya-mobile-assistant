@bdd
Feature: Transaction Builder System
  As the core differentiator of the Aya backend
  The transaction builder must correctly construct, simulate, and serialize
  unsigned transactions for client signing across all supported chains

  # References: SPEC Section 7 (Transaction Builder System) - the most important section
  # B&E Section 2.3 (Trading), SPEC Section 6 (Multi-Chain Support)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  # --- EVM Transaction Construction ---

  @phase2 @fast
  Scenario: EVM swap transaction construction
    Given the protocol adapter for Uniswap V3 on Ethereum is available
    And the user has 100 USDC on Ethereum
    When building a swap of 100 USDC for ETH
    Then the transaction contains correct calldata for Uniswap V3 Router
    And the "to" field is the Uniswap V3 SwapRouter02 address
    And the "value" field is "0" (no native token transfer for token swap)
    And gasLimit is estimated with at least 20% safety margin

  @phase2 @fast
  Scenario: ERC-20 approval required before swap
    Given the user has no USDC approval for the Uniswap V3 router
    And the user has 100 USDC on Ethereum
    When building a swap of 100 USDC for ETH
    Then the TransactionBundle contains 2 transactions
    And transaction with sequence 1 is an ERC-20 approve call
    And transaction with sequence 2 is the swap call
    And both transactions have non-empty data fields

  @phase2 @fast
  Scenario: ERC-20 approval already sufficient
    Given the user has sufficient USDC approval (>= 100 USDC) for the Uniswap V3 router
    And the user has 100 USDC on Ethereum
    When building a swap of 100 USDC for ETH
    Then the TransactionBundle contains 1 transaction
    And the transaction is the swap call only

  @phase2 @fast
  Scenario: Native token swap (ETH to USDC)
    Given the user has 5 ETH on Ethereum
    When building a swap of 1 ETH for USDC
    Then the TransactionBundle contains 1 transaction
    And the "value" field equals the ETH amount being swapped
    And no approval transaction is needed

  # --- Solana Transaction Construction ---

  @phase2 @fast
  Scenario: Solana instruction building from IDL
    Given the Marinade Finance program IDL is available
    And the user has 10 SOL
    When building a stake instruction for 10 SOL via Marinade
    Then the instruction matches the Marinade stake instruction format
    And all required accounts are resolved correctly
    And the transaction is serialized as a Solana versioned transaction

  @phase2 @fast
  Scenario: Solana swap via Jupiter
    Given the Jupiter aggregator program IDL is available
    And the user has 100 USDC on Solana
    When building a swap of 100 USDC for SOL via Jupiter
    Then the transaction contains the correct Jupiter swap instruction
    And associated token accounts are resolved

  # --- Bitcoin PSBT Construction ---

  @phase2 @fast
  Scenario: Bitcoin PSBT construction for send
    Given the user has UTXOs totaling 0.5 BTC
    When the user wants to send 0.1 BTC to a valid Bitcoin address
    Then a PSBT is constructed
    And the PSBT has appropriate input UTXOs
    And the PSBT has an output for 0.1 BTC to the destination
    And the PSBT has a change output returning to the user's address
    And the fee is estimated from mempool.space API

  @phase2 @fast
  Scenario: Bitcoin PSBT with insufficient UTXOs
    Given the user has UTXOs totaling 0.05 BTC
    When the user wants to send 0.1 BTC
    Then the transaction build fails
    And Aya informs the user of insufficient funds

  @phase2 @fast
  Scenario: Bitcoin fee estimation with safety margin
    Given the mempool.space API returns a halfHourFee of 20 sat/vB
    When estimating fees for a Bitcoin transaction
    Then the applied fee rate is at least 22 sat/vB (10% safety margin)

  # --- Transaction Simulation ---

  @phase2 @fast
  Scenario: Transaction simulation success
    Given a valid swap transaction for 100 USDC to ETH on Ethereum
    When the simulation is run via eth_call
    Then the transaction passes simulation
    And the estimated output amount is included in the response
    And simulationPassed is TRUE in the TransactionBundle

  @phase2 @fast
  Scenario: Transaction simulation failure - revert
    Given a swap transaction that will revert due to insufficient liquidity
    When the simulation is run via eth_call
    Then Aya informs the user the transaction would fail
    And provides the revert reason in human-readable form
    And does not present the transaction for signing
    And suggests alternatives (different amount, different protocol)

  @phase2 @fast
  Scenario: Transaction simulation failure - slippage
    Given a swap transaction where price has moved beyond slippage tolerance
    When the simulation is run
    Then Aya informs the user about the price movement
    And suggests updating the quote or adjusting slippage

  # --- ABI/IDL Registry ---

  @phase2 @fast
  Scenario: ABI fetched on demand and cached
    Given a contract whose ABI is not in the SQLite cache
    When a transaction is needed for that contract
    Then the ABI is fetched from the chain's block explorer API
    And the ABI is stored in SQLite
    And the ABI is loaded into the in-memory LRU cache
    And subsequent requests use the cached ABI

  @phase2 @fast
  Scenario: ABI available in cache
    Given a contract whose ABI is already in the SQLite cache
    When a transaction is needed for that contract
    Then the ABI is loaded from cache without an external API call

  @phase2 @fast
  Scenario: IDL fetched from on-chain account
    Given an Anchor program whose IDL is stored on-chain
    When the IDL is needed
    Then the IDL is fetched from the on-chain IDL account
    And cached in SQLite for future use

  @phase2 @fast
  Scenario: IDL fallback to DeployDAO
    Given a Solana program whose IDL is not on-chain
    When the IDL is needed
    Then the system falls back to the DeployDAO index
    And fetches the IDL from GitHub

  # --- Gas/Fee Estimation ---

  @phase2 @fast
  Scenario: EVM gas estimation with safety margin
    Given eth_estimateGas returns 150000 for a swap
    When the gasLimit is calculated
    Then the gasLimit is at least 180000 (150000 * 1.2)

  @phase2 @fast
  Scenario: Solana compute unit estimation
    Given a Solana transaction simulation returns 200000 compute units
    When the compute budget is set
    Then a safety margin is applied to the compute unit limit

  @phase2 @fast
  Scenario: Total fee estimate in TransactionBundle
    Given a TransactionBundle with 2 transactions
    When the totalEstimatedFee is calculated
    Then it is the sum of fees for both transactions
    And it is denominated in the chain's native token

  # --- Multi-Step Transaction Sequences ---

  @phase2 @fast
  Scenario: Approve then swap sequence
    When an EVM swap requires approval
    Then the TransactionBundle has sequence 1 (approve) and sequence 2 (swap)
    And the client must execute them in order

  @phase2 @fast
  Scenario: Bridge sequence
    When a cross-chain bridge is constructed
    Then the source chain transaction is built
    And the response explains that a claim on the destination chain will be needed later

  # --- Safety Checks ---

  @phase2 @fast
  Scenario: Unverified contract warning
    Given a target contract is not verified on the block explorer
    When the user asks to interact with it
    Then Aya warns that the contract is unverified
    And asks for explicit confirmation before building the transaction

  @phase2 @fast
  Scenario: Blacklisted contract rejection
    Given a target contract is on the blacklist
    When the user asks to interact with it
    Then Aya refuses to build the transaction
    And warns the user about the flagged address

  @phase2 @fast
  Scenario: Unusual gas warning
    Given a transaction estimates 10x more gas than typical for its type
    When the transaction is presented to the user
    Then Aya includes a warning about the unusually high gas cost

  @phase2 @fast
  Scenario Outline: Transaction construction on different EVM chains
    Given the user has funds on <chain>
    When building a swap transaction on <chain>
    Then the chainId is <chainId>
    And the correct RPC endpoint is used
    And the correct block explorer is queried for ABIs

    Examples:
      | chain    | chainId |
      | Ethereum | 1       |
      | Polygon  | 137     |
      | Arbitrum | 42161   |
      | Base     | 8453    |
      | Optimism | 10      |
