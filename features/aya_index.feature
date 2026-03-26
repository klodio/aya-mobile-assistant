@bdd @cli
Feature: Aya Index Tool Commands
  As a developer managing the protocol index
  I want aya-index commands to work correctly
  So that the seed data is always complete and correct

  # References: AYA_INDEX_SPEC.md Sections 2-5
  # AYA_INDEX_BEHAVIORS_AND_EXPECTATIONS.md Sections 2.1-2.6

  # --- Refresh ---

  @phase1 @fast
  Scenario: Refresh fetches all ABIs and IDLs
    Given a protocol_registry.yml with 3 test protocols
    When running aya-index refresh
    Then ABIs are fetched for all EVM contracts
    And IDLs are fetched for all Solana programs
    And protocol_registry.yml is updated with TVL and APY
    And validate runs automatically and passes

  @phase1 @fast
  Scenario: Refresh fails loudly on ABI fetch failure
    Given a protocol_registry.yml with a contract whose explorer API returns an error
    When running aya-index refresh
    Then the refresh aborts with a non-zero exit code
    And the error message identifies which contract on which chain failed
    And no partial seed is written

  @phase1 @fast
  Scenario: Refresh with --abis-only skips metadata
    Given a protocol_registry.yml with protocols
    When running aya-index refresh --abis-only
    Then ABIs and IDLs are fetched
    But TVL and APY metadata is NOT fetched
    And protocol_registry.yml metadata fields are not modified

  # --- Add ---

  @phase1 @fast
  Scenario: Add a new protocol
    Given an existing seed with 3 protocols
    When running aya-index add --protocol new-protocol --chain ethereum --contracts 0x1234
    Then new-protocol is added to protocol_registry.yml
    And the ABI for 0x1234 on ethereum is fetched
    And validate runs and passes

  @phase1 @fast
  Scenario: Add is idempotent for existing protocol
    Given an existing seed containing aave-v3 on ethereum
    When running aya-index add --protocol aave-v3 --chain ethereum
    Then the existing entry is updated (not duplicated)
    And a warning is printed that the entry already existed

  # --- Validate ---

  @phase1 @fast
  Scenario: Validate passes on complete seed
    Given a seed directory with all protocols, contracts, ABIs, and IDLs present
    When running aya-index validate
    Then exit code is 0
    And a success summary is printed

  @phase1 @fast
  Scenario: Validate reports all failures
    Given a seed directory missing ABIs for 3 contracts
    When running aya-index validate
    Then all 3 missing ABIs are reported (not just the first)
    And exit code is 1

  @phase1 @fast
  Scenario: Validate checks coverage rules
    Given a seed directory where BSC has no DEX protocol
    When running aya-index validate
    Then the report says BSC is missing DEX coverage
    And exit code is 1

  @phase1 @fast
  Scenario: Validate on empty seed directory
    Given an empty seed directory
    When running aya-index validate
    Then errors are reported for every missing component
    And the tool does not crash
    And exit code is 1

  # --- List ---

  @phase1 @fast
  Scenario: List shows all protocols
    Given a seed with 24 bootstrap protocols
    When running aya-index list
    Then all 24 protocols are displayed
    And each entry shows protocol name, category, chains, and actions

  @phase1 @fast
  Scenario: List shows chain coverage summary
    When running aya-index list
    Then a per-chain summary shows which protocols cover each chain
    And indicates whether coverage rules are met

  # --- Edge Cases ---

  @phase1 @fast
  Scenario: Block explorer rate limited during refresh
    Given a block explorer returns HTTP 429
    When running aya-index refresh
    Then the tool retries with exponential backoff (up to 3 retries)
    And if still rate limited, aborts with a clear error

  @phase1 @fast
  Scenario: Empty seed directory on first refresh
    Given the seed directory does not exist
    When running aya-index refresh
    Then the directory structure is created
    And all protocols are fetched from scratch
    And validate passes
