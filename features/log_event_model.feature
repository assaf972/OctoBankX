Feature: LogEvent model
  A LogEvent stores a text message and, for failures, an exception class and
  backtrace. Its kind is one of log / error / exception / notification, and it
  may optionally belong to a download.

  Scenario: Valid with a kind and a message
    When I build a log event with:
      | kind    | log           |
      | message | Job started   |
    Then the model should be valid

  Scenario: Requires a kind
    When I build a log event with:
      | message | No kind here |
    Then the model should be invalid
    And there should be a validation error on "kind"

  Scenario: Requires a message
    When I build a log event with:
      | kind | log |
    Then the model should be invalid
    And there should be a validation error on "message"

  Scenario: Rejects an unknown kind
    When I build a log event with:
      | kind    | banana   |
      | message | Whatever |
    Then the model should be invalid
    And there should be a validation error on "kind"

  Scenario Outline: Records each kind of event
    When I record a "<kind>" event with message "Something happened"
    Then the log event kind should be "<kind>"
    And the log event message should include "Something happened"

    Examples:
      | kind         |
      | log          |
      | error        |
      | notification |

  Scenario: Recording an exception captures the class, message and backtrace
    When I record an exception event with message "Statement download failed"
    Then the log event kind should be "exception"
    And the log event message should include "Statement download failed"
    And the log event error class should be "RuntimeError"
    And the log event should have a backtrace

  Scenario: An exception event without an explicit message defaults to the error text
    When I record an exception event without a message
    Then the log event kind should be "exception"
    And the log event error class should be "ArgumentError"
    And the log event message should include "bad argument"

  Scenario: A log event may belong to a download
    Given a download exists
    When I record a log event linked to that download
    Then the log event should belong to that download
