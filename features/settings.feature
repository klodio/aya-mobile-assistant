@bdd
Feature: Settings Management
  As a user of the Aya wallet
  I want to change app settings through the assistant
  So that I can configure my experience without navigating settings menus

  # References: SPEC Section 8.4 (Settings Management Tools), Section 3.3.6 (Settings Messages)
  # B&E Section 2.5 (Settings Management)

  Background:
    Given the Aya backend is running
    And the user has a valid key pair

  @phase1 @fast
  Scenario: Change default chain
    When the user says "Set my default chain to Polygon"
    Then Aya returns a SettingsChangeRequest
    And the settingKey is "defaultChain"
    And the settingValue is "polygon"
    And explanationText describes the change

  @phase1 @fast
  Scenario: Change slippage tolerance
    When the user says "Set slippage to 1%"
    Then Aya returns a SettingsChangeRequest
    And the settingKey is "slippageTolerance"
    And the settingValue is "1.0"

  @phase1 @fast
  Scenario: Change display currency
    When the user says "Show prices in EUR"
    Then Aya returns a SettingsChangeRequest
    And the settingKey is "displayCurrency"
    And the settingValue is "EUR"

  @phase1 @fast
  Scenario: Invalid slippage value - too high
    When the user says "Set slippage to 500%"
    Then Aya explains that 500% slippage is unreasonable
    And suggests a valid range (e.g., 0.1% to 50%)
    And does not return a SettingsChangeRequest

  @phase1 @fast
  Scenario: Invalid slippage value - negative
    When the user says "Set slippage to -5%"
    Then Aya explains that slippage must be a positive number
    And suggests a valid range

  @phase1 @fast
  Scenario: Unknown setting
    When the user says "Change my profile picture"
    Then Aya explains that profile picture is not a configurable setting
    And lists the available settings:
      | setting                 |
      | defaultChain            |
      | slippageTolerance       |
      | displayCurrency         |
      | notificationPreferences |
      | language                |

  @phase1 @fast
  Scenario: Confirm before disabling notifications
    When the user says "Disable all notifications"
    Then Aya asks for confirmation before returning the SettingsChangeRequest
    And the requiresConfirmation field is TRUE

  @phase1 @fast
  Scenario: Change language
    When the user says "Set language to French"
    Then Aya returns a SettingsChangeRequest
    And the settingKey is "language"
    And the settingValue is "fr"

  @phase1 @fast
  Scenario: Query current setting value
    When the user says "What is my default chain?"
    Then Aya explains that settings are stored locally on the device
    And suggests the user check the settings screen

  @phase1 @fast
  Scenario: Natural language setting change
    When the user says "I want to see everything in euros"
    Then Aya correctly interprets this as a display currency change
    And returns a SettingsChangeRequest with settingKey "displayCurrency" and settingValue "EUR"

  @phase1 @fast
  Scenario: Multiple settings in one message
    When the user says "Set my default chain to Arbitrum and slippage to 0.5%"
    Then Aya returns two SettingsChangeRequest messages
    Or handles them sequentially, confirming each one
