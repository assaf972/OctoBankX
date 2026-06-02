Feature: Exceptions are recorded as LogEvents
  Whenever an exception is raised in the app it should be captured as a
  LogEvent with the exception details.

  Scenario: A failing download records an exception LogEvent linked to the job
    Given a bank named "Bank A" exists
    And the SFTP helper raises "Connection timed out"
    And I enqueue downloads for "today"
    When I process the pending download for bank "Bank A"
    Then an exception log event should be linked to the download for bank "Bank A"

  Scenario: An unhandled web request error is recorded as an exception LogEvent
    Given the dashboard will raise when loaded
    When I request "/"
    Then the response status should be 500
    And an exception log event should exist with message containing "GET /"
