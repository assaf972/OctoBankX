Feature: Managing banks
  As an operator
  I want to register a bank with its SFTP connection details
  So that OctoBankX can download that bank's statements

  Scenario: Add a new bank through the web UI
    Given I am on the "/banks" page
    When I fill in "name" with "Capybara Test Bank"
    And I fill in "sftp_host" with "sftp.capy.test"
    And I fill in "sftp_port" with "2222"
    And I fill in "sftp_remote_path" with "/statements"
    And I submit the bank form
    Then I should see a "success" flash message
    And I should see "Capybara Test Bank"
    And I should see "sftp.capy.test"

  Scenario: An existing bank is listed
    Given a bank named "Existing Bank" exists
    When I visit "/banks"
    Then I should see "Existing Bank"

  Scenario: Reject a bank with no SFTP host
    Given I am on the "/banks" page
    When I fill in "name" with "Hostless Bank"
    And I fill in "sftp_port" with "22"
    And I submit the bank form
    Then I should see a "error" flash message

  Scenario: Reject a duplicate bank name
    Given a bank named "Duplicate Bank" exists
    And I am on the "/banks" page
    When I fill in "name" with "Duplicate Bank"
    And I fill in "sftp_host" with "sftp.dup.test"
    And I fill in "sftp_port" with "22"
    And I submit the bank form
    Then I should see a "error" flash message
