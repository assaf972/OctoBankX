Feature: Email listener job
  Ingesting statement attachments from approved senders over IMAP/POP3
  (mail servers are stubbed)

  Scenario: Does nothing when there are no active senders
    Given the email listener is configured for IMAP
    And an inactive sender "statements@leumi.co.il" for bank "Leumi"
    And the email server is stubbed but should not be used
    When the email listener runs
    Then the listener returns nothing
    And the email server should not be contacted

  Scenario: Does nothing when the host is not configured
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And the setting "email_host" is removed
    And the email server is stubbed but should not be used
    When the email listener runs
    Then the email server should not be contacted

  Scenario: Connects, downloads a CSV, and records a download (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with a message from "statements@leumi.co.il" attaching "statement_20260525.csv"
    When the email listener runs
    Then it connects to the IMAP server "imap.bank.test" on port 993
    And it logs in as "bot@bank.test"
    And it selects the "INBOX" mailbox
    And it scans all messages
    And a successful download is recorded for bank "Leumi"
    And a file named "statement_20260525.csv" should be saved
    And message 1 is marked as seen

  Scenario: Deletes an email from an unapproved sender (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with a message from "hacker@evil.com" attaching "evil.csv"
    When the email listener runs
    Then no download is recorded
    And message 1 is deleted from the server

  Scenario: Does not download the same file twice (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with a message from "statements@leumi.co.il" attaching "statement_20260525.csv"
    When the email listener runs
    And the email listener runs again
    Then 1 download should be recorded

  Scenario: Accepts an xlsx attachment (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with a message from "statements@leumi.co.il" attaching "report.xlsx"
    When the email listener runs
    Then 1 download should be recorded

  Scenario: Ignores a non-document attachment (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with a message from "statements@leumi.co.il" attaching "photo.jpg"
    When the email listener runs
    Then no download is recorded

  Scenario: Processes multiple messages (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with two messages from "statements@leumi.co.il" attaching distinct files
    When the email listener runs
    Then 2 downloads should be recorded

  Scenario: Logs out and disconnects even on error (IMAP)
    Given the email listener is configured for IMAP
    And an approved sender "statements@leumi.co.il" for bank "Leumi"
    And an IMAP inbox with a message from "statements@leumi.co.il" attaching "stmt.csv"
    And the IMAP search will raise an error
    When the email listener runs
    Then it logs out and disconnects
    And the listener raises an IMAP error

  Scenario: Downloads from approved POP3 senders and deletes the message
    Given the email listener is configured for POP3
    And an approved sender "reports@poalim.co.il" for bank "Poalim"
    And a POP3 inbox with a message from "reports@poalim.co.il" attaching "report.csv"
    When the email listener runs
    Then it connects to the POP3 server "imap.bank.test" on port 995 as "bot@bank.test"
    And a successful download is recorded for bank "Poalim"
    And the message is deleted after processing

  Scenario: Deletes unapproved POP3 senders without downloading
    Given the email listener is configured for POP3
    And an approved sender "reports@poalim.co.il" for bank "Poalim"
    And a POP3 inbox with a message from "unknown@evil.com" attaching "malware.csv"
    When the email listener runs
    Then no download is recorded
    And the message is deleted after processing

  Scenario: process_attachments saves documents and skips images
    Given the email listener is configured for IMAP
    When I process an email from "x@y.test" with attachments "file1.csv,file2.txt,file3.jpg" for bank "Leumi"
    Then 2 downloads should be recorded
    And the bank subfolder "leumi" should exist
