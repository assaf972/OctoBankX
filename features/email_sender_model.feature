Feature: EmailSender model
  Validations, predicates and scopes on the EmailSender model

  Scenario: Valid with name and a well-formed email
    When I build an email sender with:
      | sender_name  | Leumi Statements |
      | sender_email | a@b.io           |
    Then the model should be valid

  Scenario: Requires a sender name
    When I build an email sender with:
      | sender_email | a@b.io |
    Then the model should be invalid
    And there should be a validation error on "sender_name"

  Scenario: Requires a sender email
    When I build an email sender with:
      | sender_name | No Email |
    Then the model should be invalid
    And there should be a validation error on "sender_email"

  Scenario: Rejects a duplicate sender email
    Given an active email sender "dup@bank.test" exists
    When I build an email sender with:
      | sender_name  | Dup           |
      | sender_email | dup@bank.test |
    Then the model should be invalid
    And there should be a validation error on "sender_email"

  Scenario Outline: Rejects malformed email addresses
    When I build an email sender with:
      | sender_name  | Bad      |
      | sender_email | <email>  |
    Then the model should be invalid

    Examples:
      | email             |
      | not-an-email      |
      | bad email@bank.io |

  Scenario Outline: Accepts well-formed email addresses
    When I build an email sender with:
      | sender_name  | Good    |
      | sender_email | <email> |
    Then the model should be valid

    Examples:
      | email              |
      | user@bank.co.il    |
      | info+tag@bank.test |
      | a@b.io             |

  Scenario: A sender may have no bank
    When I build an email sender with:
      | sender_name  | No Bank        |
      | sender_email | nobank@b.io    |
    Then the model should be valid

  Scenario: The active? predicate reflects the active flag
    When I build an email sender with:
      | sender_name  | Active On |
      | sender_email | on@b.io   |
      | active       | true      |
    Then the email sender should be active

  Scenario: The .active scope returns only active senders
    Given an active email sender "a@test.com" exists
    And an inactive email sender "b@test.com" exists
    And an active email sender "c@test.com" exists
    When I read the active email senders
    Then the active email sender count should be 2
    And the active email senders should be "a@test.com, c@test.com"

  Scenario: Timestamps are set on create
    When I create an email sender "ts@bank.test" without explicit timestamps
    Then the created email sender has both timestamps set
