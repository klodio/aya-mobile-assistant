@bdd @cli
Feature: CLI Script Mode
  As a developer or CI pipeline
  I want to run scripted test scenarios against the Aya backend
  So that I can automate regression testing

  # References: CLI_CLIENT_SPEC Section 9 (Script Mode)
  # CLI B&E Section 2.5 (Script Execution)

  Background:
    Given the Aya backend is running

  # --- Script Execution ---

  @phase1 @fast
  Scenario: Simple script execution
    Given a script file containing:
      """
      /key default
      /portfolio default
      /session new
      What's the price of BTC?
      /assert response.contains "BTC"
      """
    When the script is executed
    Then all assertions pass
    And exit code is 0

  @phase1 @fast
  Scenario: Script with multi-turn conversation
    Given a script file containing:
      """
      /session new
      What's the price of ETH?
      /assert response.contains "ETH"
      And what about its market cap?
      /assert response.contains "market cap"
      """
    When the script is executed
    Then both messages are sent in the same session
    And all assertions pass

  @phase1 @fast
  Scenario: Script assertion failure
    Given a script file containing:
      """
      /session new
      What's the price of BTC?
      /assert response.contains "NONEXISTENT_STRING"
      """
    When the script is executed
    Then the assertion fails
    And the failure message shows the line number
    And shows what was expected vs actual
    And exit code is 1

  @phase1 @fast
  Scenario: Script with portfolio switching
    Given a script file containing:
      """
      /portfolio whale
      Swap 100 USDC for ETH
      /assert response.not_contains "insufficient"

      /portfolio empty
      Swap 100 USDC for ETH
      /assert response.contains "insufficient" OR response.contains "don't have"
      """
    When the script is executed
    Then all assertions pass

  @phase1 @fast
  Scenario: Script testing off-topic refusal
    Given a script file containing:
      """
      /session new
      Write me a poem about love
      /assert response.is_refusal
      """
    When the script is executed
    Then all assertions pass

  @phase1 @fast
  Scenario: Script testing disclaimers
    Given a script file containing:
      """
      /session new
      What's the price of ETH?
      /assert response.has_disclaimer
      """
    When the script is executed
    Then all assertions pass

  @phase2 @fast
  Scenario: Script testing transaction building
    Given a script file containing:
      """
      /portfolio default
      /session new
      Swap 100 USDC for ETH on Ethereum
      /assert response.contains "confirm"
      yes
      /assert response.has_transaction_bundle
      /assert response.simulation_passed
      """
    When the script is executed
    Then all assertions pass

  @phase1 @fast
  Scenario: Script testing latency
    Given a script file containing:
      """
      /session new
      What's the price of BTC?
      /assert response.latency < 3000
      """
    When the script is executed
    Then the latency assertion passes for a responsive backend

  @phase1 @fast
  Scenario: Script with comments and blank lines
    Given a script file containing:
      """
      # This is a comment
      /session new

      # Test a basic query
      Hello

      /assert response.contains "Aya"
      """
    When the script is executed
    Then comments and blank lines are ignored
    And the script runs correctly

  @phase1 @fast
  Scenario: Script syntax error
    Given a script file containing:
      """
      /assert this is not valid syntax !!!
      """
    When the script is executed
    Then a syntax error is reported
    And exit code is 3

  @phase1 @fast
  Scenario: Script with polyglot testing
    Given a script file containing:
      """
      /session new
      Quel est le prix du Bitcoin ?
      /assert response.contains "BTC" OR response.contains "Bitcoin"
      """
    When the script is executed
    Then all assertions pass

  # --- Exit Codes ---

  @phase1 @fast
  Scenario Outline: Script exit codes
    Given a script that <outcome>
    When the script is executed
    Then the exit code is <code>

    Examples:
      | outcome                    | code |
      | all assertions pass        | 0    |
      | has an assertion failure   | 1    |
      | cannot connect to backend  | 2    |
      | has a syntax error         | 3    |
