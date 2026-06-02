Feature: SFTP download process
  For each bank the download process logs in over SFTP, downloads the
  statement file, deletes it from the server, and — when the downloaded
  file is a ZIP archive — extracts its contents into the bank's target
  folder. (The SFTP connection is stubbed; the file and extraction are real.)

  Background:
    Given a temporary target folder

  Scenario: A ZIP statement is downloaded, deleted remotely, and extracted
    Given a bank "Leumi" configured for SFTP using that target folder
    And the remote statement is a ZIP archive containing:
      | filename      | content     |
      | statement.csv | date,amount |
      | summary.txt   | all good    |
    When the bank's statement is downloaded over SFTP for "2026-05-25"
    Then the SFTP session logs in as "octobankx"
    And the statement file is downloaded from "/statements/20260525_leumi.csv"
    And the remote statement file is deleted from the server
    And the target folder contains "statement.csv"
    And the target folder contains "summary.txt"

  Scenario: A plain (non-ZIP) statement is downloaded and deleted but not extracted
    Given a bank "Discount" configured for SFTP using that target folder
    And the remote statement is a plain CSV file
    When the bank's statement is downloaded over SFTP for "2026-05-25"
    Then the SFTP session logs in as "octobankx"
    And the statement file is downloaded from "/statements/20260525_discount.csv"
    And the remote statement file is deleted from the server
    And the target folder is empty
