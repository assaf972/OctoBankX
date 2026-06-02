Feature: Bank model
  Validations and helpers on the Bank model

  Scenario: A bank requires a name
    When I build a bank with:
      | sftp_host | sftp.bank.com |
      | sftp_port | 22            |
    Then the model should be invalid
    And there should be a validation error on "name"

  Scenario: A bank requires an SFTP host
    When I build a bank with:
      | name      | My Bank |
      | sftp_port | 22      |
    Then the model should be invalid
    And there should be a validation error on "sftp_host"

  Scenario: A bank name must be unique
    Given a bank named "Unique Bank" exists
    When I build a bank with:
      | name      | Unique Bank |
      | sftp_host | x.com       |
      | sftp_port | 22          |
    Then the model should be invalid
    And there should be a validation error on "name"

  Scenario: Two banks may share an SFTP host with different names
    Given a bank named "Bank A" exists
    When I build a bank with:
      | name             | Bank B            |
      | sftp_host        | sftp.example.test |
      | sftp_port        | 22                |
      | sftp_remote_path | /                 |
    Then the model should be valid

  Scenario Outline: SFTP port must be within range
    When I build a bank with:
      | name      | Range Bank |
      | sftp_host | h.com      |
      | sftp_port | <port>     |
    Then the model should be invalid

    Examples:
      | port  |
      | 0     |
      | 70000 |

  Scenario: A bank is valid with all required attributes
    When I build a bank with:
      | name             | Good Bank     |
      | sftp_host        | sftp.good.com |
      | sftp_port        | 22            |
      | sftp_remote_path | /statements   |
    Then the model should be valid

  Scenario: SFTP port defaults to 22
    Then a bank created with the standard details has port 22

  Scenario Outline: The sftp_url is well formed
    When I build a bank with:
      | name             | URL Bank    |
      | sftp_host        | <host>      |
      | sftp_port        | <port>      |
      | sftp_remote_path | <path>      |
    Then the bank sftp url should be "<url>"

    Examples:
      | host          | port | path        | url                                  |
      | sftp.bank.com | 22   | /statements | sftp://sftp.bank.com:22/statements   |
      | sftp.bank.com | 2222 | /data       | sftp://sftp.bank.com:2222/data       |
