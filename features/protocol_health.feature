@bdd @monitor
Feature: Protocol Health Monitoring
  As the operator of the Aya backend
  I want automated health checks for all indexed protocols
  So that the team is warned about dead contracts, exploits, and stale ABIs

  # References: SPEC Section 7.5.4 (aya-index health)
  # These scenarios run via aya-index health (CI cron, weekly)

  Background:
    Given the protocol index seed data is loaded

  # --- Contract Liveness ---

  @phase1 @monitor
  Scenario: Detect dead contract
    Given a protocol has a contract address in the index
    When eth_getCode returns empty for that address
    Then the health report marks it as RED
    And the report says "Contract not found — may have been destroyed or migrated"

  @phase1 @monitor
  Scenario: Contract is alive
    Given a protocol has a contract address in the index
    When eth_getCode returns non-empty bytecode
    Then the health report marks it as GREEN

  # --- ABI Validity ---

  @phase1 @monitor
  Scenario: ABI mismatch after contract upgrade
    Given a protocol's bundled ABI expects function selector 0xa9059cbb
    When calling that selector returns "unknown function" or reverts unexpectedly
    Then the health report marks it as YELLOW
    And the report says "ABI may be outdated — contract may have been upgraded"

  @phase1 @monitor
  Scenario: ABI still valid
    Given a protocol's bundled ABI expects a known function selector
    When calling that selector succeeds or reverts with a known error
    Then the health report marks it as GREEN

  # --- TVL Monitoring ---

  @phase1 @monitor
  Scenario: TVL dropped below warning threshold
    Given a protocol had $50M TVL when indexed
    When DeFiLlama reports TVL is now $4M
    Then the health report marks it as YELLOW
    And the report says "TVL dropped below $5M — protocol may be declining"

  @phase1 @monitor
  Scenario: TVL healthy
    Given a protocol has $100M TVL
    When DeFiLlama confirms TVL is still above $10M
    Then the health report marks it as GREEN

  # --- Exploit Detection ---

  @phase1 @monitor
  Scenario: New exploit detected
    Given a protocol was last checked on 2026-03-01
    When DeFiLlama hacks endpoint shows a new exploit on 2026-03-15
    Then the health report marks it as RED
    And the report says "New exploit detected — review immediately"

  @phase1 @monitor
  Scenario: No exploits since last check
    Given a protocol was last checked on 2026-03-01
    When DeFiLlama hacks endpoint shows no new entries
    Then the health report marks it as GREEN

  # --- Proxy Upgrade Detection ---

  @phase1 @monitor
  Scenario: Proxy implementation changed
    Given a protocol uses an upgradeable proxy
    And the last known implementation address was 0xOLD
    When the current implementation address is 0xNEW
    Then the health report marks it as YELLOW
    And the report says "Proxy implementation changed — adapter may need update"

  # --- Audit Command ---

  @phase1 @monitor
  Scenario: Audit passes for a well-established protocol
    When running aya-index audit for a protocol with:
      | criterion     | value             |
      | TVL           | $2.1B             |
      | verified      | yes               |
      | audit firm    | OpenZeppelin      |
      | last commit   | 3 days ago        |
      | deployed      | 18 months ago     |
      | exploits      | none              |
    Then the audit report shows all GREEN
    And exit code is 0

  @phase1 @monitor
  Scenario: Audit fails for a risky protocol
    When running aya-index audit for a protocol with:
      | criterion     | value             |
      | TVL           | $500K             |
      | verified      | no                |
      | audit firm    | none found        |
      | last commit   | 14 months ago     |
      | deployed      | 2 weeks ago       |
      | exploits      | 1 unresolved      |
    Then the audit report shows multiple RED
    And exit code is 1

  @phase1 @monitor
  Scenario: Audit warns on borderline protocol
    When running aya-index audit for a protocol with:
      | criterion     | value             |
      | TVL           | $15M              |
      | verified      | yes               |
      | audit firm    | not found         |
      | last commit   | 5 months ago      |
      | deployed      | 4 months ago      |
      | exploits      | none              |
    Then the audit report shows YELLOW for audit firm
    And exit code is 2

  # --- Summary Report ---

  @phase1 @monitor
  Scenario: Health summary for all protocols
    When running aya-index health for all 24 bootstrap protocols
    Then a summary is produced with counts of GREEN, YELLOW, and RED
    And each protocol has a per-check breakdown
