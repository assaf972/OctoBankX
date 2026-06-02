Feature: Dashboard and settings
  As an operator
  I want a dashboard overview and editable settings
  So that I can monitor activity and configure the system

  Scenario: The dashboard loads and lists recent downloads
    Given a download for bank "Mizrahi" with status "success" exists
    When I visit "/"
    Then I should see "Dashboard"
    And I should see "Mizrahi"

  Scenario: View an existing setting on the settings page
    Given a setting "download_dir" with value "/tmp/octobankx/downloads" exists
    When I visit "/settings"
    Then I should see "download_dir"
    And I should see "Settings"

  Scenario: Update a setting value
    Given a setting "sftp_timeout" with value "30" exists
    And I am on the "/settings" page
    When I fill in "settings[sftp_timeout]" with "60"
    And I press "Save Settings"
    Then I should see a "success" flash message
