Feature: Download job
  Enqueuing and processing SFTP downloads
  (SftpHelper.download is stubbed)

  Background:
    Given a bank named "Bank A" exists
    And a bank named "Bank B" exists

  Scenario: Enqueue creates one pending download per bank
    When I enqueue downloads for "today"
    Then there should be 2 downloads for "today"
    And every download for "today" should have status "pending"

  Scenario: Enqueue is idempotent for the same date
    When I enqueue downloads for "today"
    And I enqueue downloads for "today" again
    Then the download count should be unchanged

  Scenario: Enqueue works independently per date
    When I enqueue downloads for "today"
    And I enqueue downloads for "tomorrow"
    Then there should be 2 downloads for "tomorrow"

  Scenario: Processing a pending download marks it successful
    Given the SFTP helper succeeds for every bank
    And I enqueue downloads for "today"
    When I process the pending download for bank "Bank A"
    Then the download for bank "Bank A" should have status "success"
    And the download for bank "Bank A" should have started and completed timestamps

  Scenario: A failing download is marked failed and does not raise
    Given the SFTP helper raises "Connection timed out"
    And I enqueue downloads for "today"
    When I process the pending download for bank "Bank A"
    Then the download for bank "Bank A" should have status "failed"
    And the download for bank "Bank A" should have error message "Connection timed out"

  Scenario: Running the job processes all banks
    Given the SFTP helper succeeds for every bank
    When I run the download job for "today"
    Then there should be 2 downloads for "today"
    And every download for "today" should have status "success"

  Scenario: The job uses download_dir and timeout from settings
    Given the SFTP helper succeeds for every bank
    And a setting "download_dir" with value "/custom/path" exists
    And a setting "sftp_timeout" with value "60" exists
    When I run the download job for "today"
    Then the SFTP helper should have been called 2 times
    And every SFTP call used download_dir "/custom/path"
    And every SFTP call used timeout 60

  Scenario: The job skips banks that already have a download for the date
    Given the SFTP helper succeeds for every bank
    And a download for bank "Bank A" with status "success" exists
    When I run the download job for "today"
    Then there should be 1 download for bank "Bank A" on "today"
    And there should be 1 download for bank "Bank B" on "today"

  Scenario: One bank failing does not stop the others
    Given the SFTP helper fails for bank "Bank A" and succeeds otherwise
    When I run the download job for "today"
    Then the download for bank "Bank A" on "today" should have status "failed"
    And the download for bank "Bank B" on "today" should have status "success"
    And the SFTP helper should have been called 2 times

  Scenario: Running with no date defaults to today
    Given the SFTP helper succeeds for every bank
    When I run the download job with no date
    Then there should be 2 downloads for "today"
