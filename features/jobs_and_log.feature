Feature: Monitoring download jobs and history
  As an operator
  I want to see download jobs and filter the history
  So that I can monitor which bank statements were retrieved

  Scenario: The jobs page shows a download with its status badge
    Given a download for bank "Poalim" with status "success" exists
    When I visit "/jobs"
    Then I should see "Poalim"
    And I should see a "success" status badge

  Scenario: Filter jobs by status
    Given a download for bank "GreenBank" with status "success" exists
    And a download for bank "RedBank" with status "failed" exists
    When I visit "/jobs?status=success"
    Then I should see "GreenBank"
    And I should not see "RedBank"

  Scenario: Trigger the download job from the jobs page
    Given I am on the "/jobs" page
    When I press "Run Now"
    Then I should see a "success" flash message

  Scenario: Filter the log by bank
    Given a download for bank "Discount" with status "success" exists
    And a download for bank "Fibi" with status "failed" exists
    When I visit "/log"
    Then I should see "Discount"
    And I should see "Fibi"
