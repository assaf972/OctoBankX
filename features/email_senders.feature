Feature: Managing approved email senders
  As an operator
  I want to approve the email addresses that may send statements
  So that the email listener only ingests attachments from trusted banks

  Background:
    Given a bank named "Leumi" exists

  Scenario: Add an approved sender linked to a bank
    Given I am on the "/email_senders" page
    When I fill in "sender_name" with "Leumi Statements"
    And I fill in "sender_email" with "statements@leumi.test"
    And I select "Leumi" from "bank_id"
    And I press "Add Sender"
    Then I should see a "success" flash message
    And I should see "statements@leumi.test"
    And I should see a "success" status badge

  Scenario: Reject an invalid email address
    Given I am on the "/email_senders" page
    When I fill in "sender_name" with "Bad Sender"
    And I fill in "sender_email" with "not-an-email"
    And I press "Add Sender"
    Then I should see a "error" flash message

  Scenario: Deactivate an approved sender
    Given an email sender "statements@discount.test" for bank "Leumi" exists
    And I am on the "/email_senders" page
    When I deactivate the email sender "statements@discount.test"
    Then I should see a "success" flash message
    And I should see "Inactive"

  Scenario: Remove an approved sender
    Given an email sender "statements@fibi.test" for bank "Leumi" exists
    And I am on the "/email_senders" page
    When I delete the email sender "statements@fibi.test"
    Then I should see a "success" flash message
    And I should not see "statements@fibi.test"
