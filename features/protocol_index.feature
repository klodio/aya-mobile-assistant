@bdd
Feature: Protocol Index and Yield Discovery
  As a user of the Aya wallet
  I want the assistant to know which DeFi protocols are available
  So that it can find the best yield, orchestrate multi-step operations,
  and answer questions about DeFi opportunities across chains

  # References: SPEC Section 7.2 (Protocol Index), Section 7.4 (LLM Tools for Protocol Discovery)
  # The protocol index is pre-populated (bundled seed) + on-demand fetch. No background daemon.

  Background:
    Given the Aya backend is running
    And the user has a valid key pair
    And the protocol index is loaded with seed data

  # --- Yield Discovery ---

  @phase1 @fast
  Scenario: Best yield for ETH
    When the user asks "Where is the best yield for my ETH?"
    Then Aya calls get_best_yield with asset ETH
    And returns a ranked list of yield opportunities
    And each entry includes protocol name, chain, APY, and risk level
    And the list is sorted by APY descending
    And includes a financial disclaimer

  @phase1 @fast
  Scenario: Best yield for ETH on a specific chain
    When the user asks "Best yield for ETH on Ethereum?"
    Then Aya calls get_best_yield with asset ETH and chain ETHEREUM
    And only returns protocols deployed on Ethereum

  @phase1 @fast
  Scenario: Best yield with risk filter
    When the user asks "What's the safest yield for my USDC?"
    Then Aya calls get_best_yield with asset USDC and maxRisk low
    And only returns low-risk protocols
    And includes a disclaimer

  @phase1 @fast
  Scenario: Best yield for SOL
    When the user asks "How can I earn yield on my SOL?"
    Then Aya returns staking options on Solana (Marinade, etc.)
    And shows current APYs
    And compares the options

  @phase1 @fast
  Scenario: No yield available for exotic asset
    When the user asks "Where is the best yield for TOKEN_XYZ?"
    And no protocols in the index support TOKEN_XYZ yield
    Then Aya explains that no yield opportunities were found for TOKEN_XYZ
    And suggests alternatives or checking back later

  # --- Protocol Discovery ---

  @phase1 @fast
  Scenario: Search staking protocols
    When the user asks "What staking options are there for ETH?"
    Then Aya calls search_protocols with category staking and asset ETH
    And returns protocols like Lido and Rocket Pool with APYs

  @phase1 @fast
  Scenario: Search DEXes on a chain
    When the user asks "What DEXes are available on Polygon?"
    Then Aya calls search_protocols with category dex and chain POLYGON
    And returns protocols like Uniswap V3, Curve, QuickSwap

  @phase1 @fast
  Scenario: Search lending protocols
    When the user asks "Where can I lend my USDC?"
    Then Aya calls search_protocols with category lending and asset USDC
    And returns protocols like Aave V3 across multiple chains with APYs

  @phase1 @fast
  Scenario: Search bridge protocols
    When the user asks "How can I bridge to Arbitrum?"
    Then Aya calls search_protocols with category bridge and chain ARBITRUM
    And returns bridge options like LI.FI

  @phase1 @fast
  Scenario: Protocol info query
    When the user asks "Tell me about Aave V3 on Polygon"
    Then Aya calls get_protocol_info with protocol aave-v3 and chain POLYGON
    And returns description, supported actions, current APY, TVL, and risk level

  # --- Multi-Step Orchestration ---

  @phase2 @fast
  Scenario: Bridge and stake in one conversation
    Given the user has 500 USDC on Ethereum
    When the user says "Bridge my USDC to Arbitrum and stake into the best yield"
    Then Aya calls get_best_yield for USDC on ARBITRUM
    And identifies the best protocol (e.g., Aave V3 at 3.1%)
    And explains the two-step plan:
      | step | action                               |
      | 1    | Bridge 500 USDC from Ethereum to Arbitrum |
      | 2    | Deposit 500 USDC into Aave V3 on Arbitrum |
    And asks for confirmation
    And mentions the yield and risk level

  @phase2 @fast
  Scenario: Swap and stake in one conversation
    Given the user has 2 ETH on Ethereum
    When the user says "Swap 1 ETH for stETH"
    Then Aya recognizes this as a Lido staking operation
    And builds the Lido stake transaction
    And shows estimated APY from the protocol index

  @phase2 @fast
  Scenario: Compare yields then execute
    When the user asks "Compare staking yields for ETH"
    Then Aya returns a comparison table
    When the user says "Stake with the first one"
    Then Aya initiates the staking flow with the top-yield protocol

  # --- Live Data Augmentation ---

  @phase1 @fast
  Scenario: APY data is live, not stale from seed
    When the user asks for the best yield
    Then the APY values are fetched from DeFiLlama at runtime
    And not solely from the bundled seed data
    And the response includes the data freshness

  @phase1 @fast
  Scenario: TVL data is live
    When the user asks "What's the TVL of Aave?"
    Then TVL is fetched from DeFiLlama at runtime
    And the protocol index provides the structural metadata (chains, actions, risk)

  # --- Seed Data Coverage ---

  @phase1 @fast
  Scenario: Bundled ABIs cover all protocol adapters
    Given the protocol index has entries for all supported protocols
    Then every protocol's contract addresses have corresponding ABIs in the seed
    And no bundled protocol requires an on-demand ABI fetch on first use

  @phase1 @fast
  Scenario: On-demand ABI fetch for unknown contract
    Given a contract address not in the bundled seed
    When the LLM's build_transaction targets that contract
    Then the ABI is fetched from the chain's block explorer
    And cached in SQLite for future use
    And the user is warned if the contract is unverified

  @phase1 @fast
  Scenario Outline: Protocol index covers key protocols
    Then the protocol index contains an entry for <protocol> on <chain>
    And the entry has category <category>

    Examples:
      | protocol    | chain    | category |
      | uniswap-v3  | Ethereum | dex      |
      | uniswap-v3  | Polygon  | dex      |
      | uniswap-v3  | Arbitrum | dex      |
      | aave-v3     | Ethereum | lending  |
      | aave-v3     | Polygon  | lending  |
      | aave-v3     | Arbitrum | lending  |
      | lido        | Ethereum | staking  |
      | curve       | Ethereum | dex      |
      | 1inch       | Ethereum | dex      |
      | lifi        | Ethereum | bridge   |
      | jupiter     | Solana   | dex      |
      | marinade    | Solana   | staking  |
      | raydium     | Solana   | dex      |
