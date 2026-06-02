Feature: System status API
  As an external monitor
  I want a JSON health endpoint
  So that I can check OctoBankX is up and see basic counts

  Scenario: Status endpoint reports a healthy system
    When I request "/api/v1/status"
    Then the response status should be 200
    And the JSON field "status" should equal "ok"

  Scenario: Status reflects the number of registered banks
    Given a bank named "Acme Bank" exists
    When I request "/api/v1/status"
    Then the response status should be 200
    And the JSON field "banks_count" should equal "1"
