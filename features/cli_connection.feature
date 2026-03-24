@bdd @cli
Feature: CLI Connection and Startup
  As a developer testing the Aya backend
  I want the CLI to connect reliably to the backend
  So that I can start testing quickly

  # References: CLI_CLIENT_SPEC Section 6 (HTTP Transport), Section 8 (REPL)
  # CLI B&E Section 2.1 (Connection & Startup)

  @phase1 @fast
  Scenario: Connect to running backend
    Given the Aya backend is running on http://localhost:8080
    When the CLI starts with --url http://localhost:8080
    Then the CLI connects successfully
    And displays the connection status including URL and key info

  @phase1 @fast
  Scenario: Backend unreachable
    Given no backend is running on http://localhost:9999
    When the CLI starts with --url http://localhost:9999
    Then the CLI displays "Cannot connect to http://localhost:9999"
    And suggests checking if the backend is running

  @phase1 @fast
  Scenario: Backend unreachable in script mode
    Given no backend is running
    When a script is executed with --url http://localhost:9999
    Then the script exits with code 2

  @phase1 @fast
  Scenario: Auto-generate default key on first run
    Given no keys exist in ~/.aya-cli/keys/
    When the CLI starts for the first time
    Then a default secp256k1 key pair is generated
    And saved to ~/.aya-cli/keys/default.pem
    And the public key is displayed

  @phase1 @fast
  Scenario: Load existing key
    Given a key named "alice" exists in ~/.aya-cli/keys/
    When the CLI starts with --key alice
    Then the CLI uses alice's key pair for signing

  @phase1 @fast
  Scenario: Generate new named key
    When the user runs /key generate bob
    Then a new key pair is generated
    And saved as bob.pem
    And the CLI switches to using bob's key

  @phase1 @fast
  Scenario: Custom URL via environment variable
    Given AYA_CLI_URL is set to http://custom:8080
    When the CLI starts without --url
    Then the CLI connects to http://custom:8080
