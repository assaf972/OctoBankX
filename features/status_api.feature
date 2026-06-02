Feature: Status JSON API
  System health snapshot via /api/v1/status

  Scenario: Status returns JSON with ok and a timestamp
    When I request "/api/v1/status"
    Then the response status should be 200
    And the response content type should include "application/json"
    And the JSON field "status" should equal "ok"
    And the JSON field "timestamp" should not be null

  Scenario: Status reports the number of banks
    Given a bank named "Acme Bank" exists
    When I request "/api/v1/status"
    Then the JSON field "banks_count" should equal the number 1

  Scenario: Totals cover all four statuses
    When I request "/api/v1/status"
    Then the JSON totals should cover all four statuses

  Scenario: Totals count downloads by status
    Given a download for bank "Bank A" with status "success" exists
    And a download for bank "Bank A" with status "success" exists
    And a download for bank "Bank A" with status "failed" exists
    When I request "/api/v1/status"
    Then the JSON field "totals.success" should equal the number 2
    And the JSON field "totals.failed" should equal the number 1
    And the JSON field "totals.pending" should equal the number 0

  Scenario: Today section is scoped to the current date
    When I request "/api/v1/status"
    Then the JSON field "today.date" should equal the current date

  Scenario: last_success and last_failure are null with no downloads
    When I request "/api/v1/status"
    Then the JSON field "last_success" should be null
    And the JSON field "last_failure" should be null

  Scenario: Totals are all zero with no downloads
    When I request "/api/v1/status"
    Then the JSON field "totals.success" should equal the number 0
    And the JSON field "totals.failed" should equal the number 0
    And the JSON field "totals.pending" should equal the number 0
    And the JSON field "totals.running" should equal the number 0
