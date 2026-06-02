Feature: Downloads JSON API
  Listing, fetching, enqueuing and updating downloads via /api/v1/downloads

  Scenario: Listing returns JSON
    When I request "/api/v1/downloads"
    Then the response status should be 200
    And the response content type should include "application/json"

  Scenario: Listing is an empty array when there are no downloads
    When I request "/api/v1/downloads"
    Then the JSON response should be an empty array

  Scenario: Listing returns all downloads
    Given a download for bank "Bank A" with status "success" exists
    And a download for bank "Bank A" with status "failed" exists
    When I request "/api/v1/downloads"
    Then the JSON array should have 2 items

  Scenario: Each record exposes the expected fields
    Given a download for bank "Bank A" with status "success" exists
    When I request "/api/v1/downloads"
    Then each JSON item should include the keys "id, bank_id, bank_name, date, status, error_message, file_path"

  Scenario Outline: Listing can be filtered by status
    Given a download for bank "Bank A" with status "<keep>" exists
    And a download for bank "Bank A" with status "<drop>" exists
    When I request "/api/v1/downloads?status=<keep>"
    Then the JSON array should have 1 items
    And every JSON item should have "status" equal to "<keep>"

    Examples:
      | keep    | drop    |
      | pending | success |
      | success | failed  |
      | failed  | success |

  Scenario: Fetching a single download by id
    Given a download for bank "Bank A" with status "success" exists
    When I request the latest download by id
    Then the response status should be 200
    And the JSON field "status" should equal "success"

  Scenario: Fetching a missing id returns 404
    When I request "/api/v1/downloads/999999"
    Then the response status should be 404

  Scenario: Enqueuing a download for a bank returns 201
    Given a bank named "Bank A" exists
    When I enqueue a download via the API for bank "Bank A" on "2026-06-02"
    Then the response status should be 201
    And the JSON field "status" should equal "pending"
    And the JSON field "date" should equal "2026-06-02"

  Scenario: Enqueuing defaults the date to today
    Given a bank named "Bank A" exists
    When I enqueue a download via the API for bank "Bank A" with no date
    Then the response status should be 201

  Scenario: Enqueuing without a bank id returns 422
    When I enqueue a download via the API with an empty body
    Then the response status should be 422
    And the JSON response should include "bank_id"

  Scenario: Enqueuing for a non-existent bank returns 404
    When I enqueue a download via the API for a non-existent bank
    Then the response status should be 404

  Scenario: Enqueuing a duplicate for the same bank and date returns 409
    Given a bank named "Bank A" exists
    And a download for bank "Bank A" with status "pending" exists
    When I enqueue a download via the API for bank "Bank A" today
    Then the response status should be 409

  Scenario: Updating status to running sets a started time
    Given a download for bank "Bank A" with status "pending" exists
    When I patch the latest download status to "running"
    Then the response status should be 200
    And the JSON field "status" should equal "running"
    And the JSON field "started_at" should not be null

  Scenario: Updating status to success records a file path
    Given a download for bank "Bank A" with status "pending" exists
    When I patch the latest download with JSON:
      """
      { "status": "success", "file_path": "/data/stmt.csv" }
      """
    Then the JSON field "status" should equal "success"
    And the JSON field "file_path" should equal "/data/stmt.csv"
    And the JSON field "completed_at" should not be null

  Scenario: Updating status to failed records an error message
    Given a download for bank "Bank A" with status "pending" exists
    When I patch the latest download with JSON:
      """
      { "status": "failed", "error_message": "SFTP timeout" }
      """
    Then the JSON field "status" should equal "failed"
    And the JSON field "error_message" should equal "SFTP timeout"

  Scenario: An invalid status value is rejected
    Given a download for bank "Bank A" with status "pending" exists
    When I patch the latest download status to "unknown"
    Then the response status should be 422

  Scenario: Patching a missing download returns 404
    When I patch the status of download 999999 to "running"
    Then the response status should be 404
