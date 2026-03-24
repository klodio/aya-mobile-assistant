@bdd
Feature: Market Data Queries
  As a user of the Aya wallet
  I want to ask about prices, market conditions, and protocol metrics
  So that I can make informed decisions about my crypto assets

  # References: SPEC Section 8.2 (Market Data Tools), Section 4 (Agent Pipeline)
  # B&E Section 2.2 (Market Data & Information)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair
    And market data APIs are available

  @phase1 @fast
  Scenario: Single asset price query
    When the user asks "What is the price of BTC?"
    Then Aya returns the current BTC price in USD
    And the response includes the 24-hour price change percentage
    And the data source is attributed
    And the response includes a financial disclaimer

  @phase1 @fast
  Scenario: Multi-asset price query
    When the user asks "Show me prices for ETH, SOL, and AVAX"
    Then Aya returns prices for all three assets
    And each price includes the 24-hour change
    And sources are attributed

  @phase1 @fast
  Scenario: Price query with display currency
    Given the user's display currency is set to EUR
    When the user asks "What is the price of ETH?"
    Then Aya returns the ETH price in EUR

  @phase1 @fast
  Scenario: Top gainers query
    When the user asks "What are today's top gainers?"
    Then Aya returns a list of top gaining assets
    And each entry includes the symbol, price, and percentage change
    And the list is sorted by 24h change descending

  @phase1 @fast
  Scenario: Top losers query
    When the user asks "Show me the biggest losers today"
    Then Aya returns a list of top losing assets sorted by 24h change ascending

  @phase1 @fast
  Scenario: TVL query for a DeFi protocol
    When the user asks "What's the TVL of Aave?"
    Then Aya queries DeFiLlama
    And returns the total TVL for Aave
    And optionally includes a per-chain breakdown
    And the source is attributed as DeFiLlama

  @phase1 @fast
  Scenario: Market overview query
    When the user asks "How's the market doing?"
    Then Aya provides a summary of overall market conditions
    And mentions total crypto market cap
    And mentions BTC dominance
    And includes a disclaimer

  @phase1 @fast
  Scenario: Unknown asset query
    When the user asks "What's the price of XYZNONEXISTENT?"
    Then Aya responds that the asset was not found
    And suggests checking the asset name or ticker

  @phase1 @fast
  Scenario: Asset with ambiguous ticker in price query
    When the user asks "What's the price of UNI?"
    And multiple tokens match the ticker "UNI"
    Then Aya returns the price of the most prominent UNI (Uniswap)
    And mentions the full name to avoid confusion

  @phase1
  Scenario: Stale data warning
    Given the market data API is responding with data older than 60 seconds
    When the user asks for a price
    Then the response includes a data freshness warning
    And mentions the age of the data

  @phase2 @fast
  Scenario: Aya Trade market data as primary source
    Given Aya Trade market data API is available
    And Aya Trade lists ETH/USDT
    When the user asks "What's the price of ETH?"
    Then Aya Trade is the primary data source
    And the source is attributed as Aya Trade

  @phase2 @fast
  Scenario: Aya Trade fallback to CoinGecko
    Given Aya Trade market data API is available
    But Aya Trade does not list TOKEN_X
    When the user asks "What's the price of TOKEN_X?"
    Then Aya falls back to CoinGecko
    And the source is attributed as CoinGecko

  # --- CoinGecko Pro / Free Failover ---

  @phase1 @fast
  Scenario: CoinGecko Pro as primary source
    Given CoinGecko Pro API key is configured
    And CoinGecko Pro is available
    When the user asks "What's the price of BTC?"
    Then data is fetched from CoinGecko Pro (pro-api.coingecko.com)
    And the source is attributed

  @phase1 @fast
  Scenario: Fallback to CoinGecko Free when Pro fails
    Given CoinGecko Pro API key is configured
    But CoinGecko Pro returns HTTP 429 (rate limited)
    When the user asks "What's the price of BTC?"
    Then data is fetched from CoinGecko Free (api.coingecko.com)
    And the source attribution mentions free tier

  @phase1 @fast
  Scenario: Fallback to CoinGecko Free when Pro key is missing
    Given no CoinGecko Pro API key is configured
    When the user asks "What's the price of BTC?"
    Then data is fetched from CoinGecko Free
    And no Pro API call is attempted

  @phase1 @fast
  Scenario: Both CoinGecko tiers down
    Given CoinGecko Pro is returning errors
    And CoinGecko Free is also returning errors
    When the user asks "What's the price of BTC?"
    Then Aya returns a MARKET_DATA_ERROR
    And the message explains market data is temporarily unavailable

  @phase1 @fast
  Scenario: CoinGecko Pro circuit breaker
    Given CoinGecko Pro has failed 5 consecutive times in the last minute
    When the user asks for a price
    Then CoinGecko Pro is skipped (circuit breaker open)
    And CoinGecko Free is used directly
    And latency is not wasted on the known-down Pro endpoint

  # --- Caching ---

  @phase1 @fast
  Scenario: Market data caching within TTL
    Given the user asked "What's the price of BTC?" 10 seconds ago
    When the user asks "What's the price of BTC?" again
    Then the response uses cached data
    And does not make a new external API call

  @phase1 @fast
  Scenario Outline: Price query for various assets
    When the user asks "What's the price of <asset>?"
    Then Aya returns a valid price for <asset>
    And the response includes a 24h change percentage

    Examples:
      | asset |
      | BTC   |
      | ETH   |
      | SOL   |
      | MATIC |
      | AVAX  |
      | BNB   |

  # --- Token Info Tool ---

  @phase1 @fast
  Scenario: Token info lookup by symbol
    When the user asks "Tell me about Chainlink"
    Then Aya calls get_token_info
    And returns the full name, symbol (LINK), decimals, chains, and contract addresses
    And includes a brief description of the token

  @phase1 @fast
  Scenario: Token info lookup by contract address
    When the user asks "What token is at 0x514910771AF9Ca656af840dff83E8264EcF986CA?"
    Then Aya identifies it as Chainlink (LINK) on Ethereum
    And returns full token details

  # --- News Tool ---

  @phase1 @fast
  Scenario: Crypto news query
    When the user asks "What's the latest crypto news?"
    Then Aya calls get_news via CoinGecko
    And returns a list of recent headlines with summaries
    And includes a disclaimer

  @phase1 @fast
  Scenario: Asset-specific news
    When the user asks "Any news about Ethereum?"
    Then Aya calls get_news with symbol ETH
    And returns Ethereum-related news headlines

  # --- Balance Check Tool ---

  @phase1 @fast
  Scenario: Direct balance check
    Given the user has 5 ETH on Ethereum in their portfolio
    When the user asks "How much ETH do I have?"
    Then Aya calls check_balance with symbol ETH and chain ETHEREUM
    And returns the balance (5 ETH) with USD value

  # --- Aya Trade Check Tool ---

  @phase2 @fast
  Scenario: Aya Trade availability check
    Given Aya Trade is available
    When the user wants to swap ETH for USDC
    Then the LLM calls check_aya_trade with baseAsset ETH and quoteAsset USDC
    And the response includes whether the pair is available on Aya Trade
