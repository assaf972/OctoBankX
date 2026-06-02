Feature: Job detail page
  From the jobs list I can open a single job to see its details — name,
  status, timing, error, log and backtrace — and rerun, kill or delete it.

  Scenario: Open a job from the jobs list
    Given a failed job for bank "Leumi" exists
    When I open that job from the jobs list
    Then I should see "Job"
    And I should see "Leumi"
    And I should see a "failed" status badge

  Scenario: The detail page shows error, log and backtrace in code blocks
    Given a failed job for bank "Leumi" exists
    When I open that job detail page
    Then I should see "SFTP authentication failed for user@host"
    And I should see "Connecting to host"
    And I should see "jobs/download_job.rb:50"
    And I should see a code block

  Scenario: Rerun a failed job
    Given a failed job for bank "Leumi" exists
    And the SFTP helper succeeds for every bank
    When I open that job detail page
    And I press "Rerun"
    Then I should see a "success" flash message
    And the job should now have status "success"

  Scenario: Kill a running job
    Given a running job for bank "Poalim" exists
    When I open that job detail page
    And I press "Kill"
    Then I should see a "success" flash message
    And the job should now have status "failed"
    And I should see "Killed by user"

  Scenario: Delete a job
    Given a successful job for bank "Discount" exists
    When I open that job detail page
    And I press "Delete"
    Then I should see a "success" flash message
    And the job should no longer exist
