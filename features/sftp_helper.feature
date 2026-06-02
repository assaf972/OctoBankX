Feature: SFTP helper
  Building statement filenames and downloading files over SFTP
  (the SFTP connection is stubbed — no real server is used)

  Scenario Outline: The statement filename is YYYYMMDD_<slug>.csv
    When I build the statement filename for a bank named "<name>" on "2026-05-25"
    Then the statement filename should be "<filename>"

    Examples:
      | name         | filename                  |
      | בנק לאומי     | 20260525_בנק_לאומי.csv     |
      | Bank Leumi   | 20260525_bank_leumi.csv   |
      | My  Big  Bank| 20260525_my_big_bank.csv  |

  Scenario: A successful download returns a local path and connects with the bank credentials
    Given a bank "Leumi" with host "sftp.leumi.co.il" port 22 path "/statements" user "octobankx" password "secret123"
    And the SFTP server accepts the connection
    When I download statements for the bank on "2026-05-25"
    Then the download returns a csv path inside the download directory
    And it connected to host "sftp.leumi.co.il" as user "octobankx" on port 22
    And it requested the remote file "/statements/20260525_leumi.csv"
    And the local directory "Leumi" should exist under the download directory

  Scenario: A non-standard port is passed through
    Given a bank "Custom" with host "sftp.custom.co.il" port 2222 path "/daily" user "user" password "pass"
    And the SFTP server accepts the connection
    When I download statements for the bank on "2026-05-25"
    Then it connected to host "sftp.custom.co.il" as user "user" on port 2222

  Scenario Outline: SFTP failures raise descriptive errors
    Given a bank "Errs" with host "h.test" port 22 path "/" user "u" password "p"
    And the SFTP connection raises "<kind>"
    When I download statements for the bank on "2026-05-25"
    Then the download fails with a message matching "<pattern>"

    Examples:
      | kind                    | pattern                     |
      | authentication failure  | SFTP authentication failed  |
      | a missing remote file   | SFTP status error           |
      | a refused connection    | SFTP connection failed      |
      | a socket error          | SFTP connection failed      |
      | an unexpected error     | SFTP error                  |
