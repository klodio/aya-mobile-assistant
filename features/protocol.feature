@bdd
Feature: SBE Protocol
  As the communication layer between client and server
  The SBE protocol must correctly encode, decode, and version-negotiate
  all message types between the React Native client and the Java backend

  # References: SPEC Section 3 (SBE Protocol Definition)
  # B&E related: data integrity guardrails

  Background:
    Given the Aya backend is running

  # --- Encoding / Decoding ---

  @phase1 @fast
  Scenario: Valid SBE AssistantRequest decoded
    Given a properly SBE-encoded AssistantRequest
    With a valid messageType, sessionId, publicKey, and signature
    When received by the server
    Then it is decoded without error
    And all fields are correctly extracted

  @phase1 @fast
  Scenario: Invalid SBE payload rejected
    Given a malformed binary payload that is not valid SBE
    When received by the server
    Then an ErrorResponse with errorCategory VALIDATION is returned
    And the message indicates the request could not be decoded

  @phase1 @fast
  Scenario: Empty payload rejected
    Given a request with an empty binary body
    When received by the server
    Then an ErrorResponse with errorCategory VALIDATION is returned

  @phase1 @fast
  Scenario Outline: All message types round-trip correctly
    Given a valid <messageType> message with representative data
    When the message is encoded to SBE bytes
    And then decoded back
    Then the decoded message matches the original

    Examples:
      | messageType             |
      | UserMessage             |
      | AssistantTextResponse   |
      | ClientActionRequest     |
      | TransactionBundle       |
      | MarketDataResponse      |
      | TradingStrategyResponse |
      | SettingsChangeRequest   |
      | ErrorResponse           |
      | TransactionStatus       |

  @phase1 @fast
  Scenario: UserMessage with portfolio group round-trip
    Given a UserMessage with 5 portfolio entries across different chains
    When encoded and decoded
    Then all 5 portfolio entries are preserved
    And each entry's chainId, address, asset, contractAddress, and balance are correct

  @phase1 @fast
  Scenario: TransactionBundle with multiple transactions round-trip
    Given a TransactionBundle with 3 transactions in sequence
    When encoded and decoded
    Then all 3 transactions are preserved in order
    And each transaction's sequence, to, data, value, gasLimit, and description are correct

  # --- Version Negotiation ---

  @phase1 @fast
  Scenario: Client and server at same version
    Given the client sends schemaVersion 1
    And the server supports schema version 1
    When a request is processed
    Then the response has schemaVersion 1

  @phase1 @fast
  Scenario: Client at older version than server
    Given the client sends schemaVersion 1
    And the server supports schema versions 1 through 3
    When a request is processed
    Then the response is encoded at schemaVersion 1
    And new fields from versions 2 and 3 are not included

  @phase1 @fast
  Scenario: Client at newer version than server
    Given the client sends schemaVersion 3
    And the server supports schema versions 1 through 2
    When a request is processed
    Then the server ignores unknown fields from version 3
    And the response is encoded at schemaVersion 2

  @phase1 @fast
  Scenario: Unknown fields in older message tolerated
    Given a message encoded at schema version 3 with a new field
    And the decoder is at schema version 2
    When the message is decoded
    Then the decoder ignores the unknown field
    And successfully decodes all known fields

  # --- Request/Response Correlation ---

  @phase1 @fast
  Scenario: Request ID echoed in response
    Given a request with requestId 12345
    When the response is sent
    Then the response has requestId 12345

  @phase1 @fast
  Scenario: Unique request IDs for concurrent requests
    Given two concurrent requests with requestId 1001 and requestId 1002
    When both responses are sent
    Then response for request 1001 has requestId 1001
    And response for request 1002 has requestId 1002

  # --- Streaming Protocol (Phase 2) ---

  @phase2 @fast
  Scenario: Text streaming chunk assembly
    Given a streaming response for a text query
    When multiple StreamChunk messages with chunkType TEXT_DELTA arrive
    Then they are concatenated in sequenceNumber order into the full text
    And the final chunk has isFinal TRUE

  @phase2 @fast
  Scenario: Transaction partial buffered until final
    Given a streaming response that includes a TransactionBundle
    When StreamChunk messages with chunkType TRANSACTION_PARTIAL arrive
    Then the client buffers all chunks
    And only renders the transaction when isFinal TRUE is received

  @phase2 @fast
  Scenario: Streaming error mid-response
    Given a streaming response encounters an error at chunk 5
    When the error occurs
    Then a final StreamChunk with error information is sent
    And isFinal is TRUE
    And the WebSocket connection is closed gracefully

  @phase2 @fast
  Scenario: WebSocket connection established
    When the client connects to the streaming endpoint
    Then a WebSocket connection is established
    And binary SBE frames can be sent and received

  # --- Enum Handling ---

  @phase1 @fast
  Scenario: Known enum values decoded correctly
    Given a message with ChainId set to ETHEREUM (1)
    When decoded
    Then the ChainId field equals ETHEREUM

  @phase1 @fast
  Scenario: Unknown enum value handled gracefully
    Given a message with ChainId set to value 99999 (unknown)
    When decoded by an older client
    Then the decoder does not crash
    And the field is treated as an unknown value

  # --- ACTION_PARTIAL Chunk Type ---

  @phase2 @fast
  Scenario: Action partial chunk buffered until final
    Given a streaming response that includes a ClientActionRequest
    When StreamChunk messages with chunkType ACTION_PARTIAL arrive
    Then the client buffers all chunks
    And only renders the action when isFinal TRUE is received

  # --- Streaming Error Signaling ---

  @phase2 @fast
  Scenario: Streaming error contains human-readable message
    Given a streaming response encounters an error
    When the final error chunk is received
    Then chunkType is TEXT_DELTA
    And isFinal is TRUE
    And the payload contains a human-readable error message
    And the WebSocket close code indicates an error
