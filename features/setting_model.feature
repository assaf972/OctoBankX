Feature: Setting model
  Key/value configuration store: validations, reads and upserts

  Scenario: A setting requires a key
    When I build a setting with no key
    Then the model should be invalid
    And there should be a validation error on "key"

  Scenario: A setting key must be unique
    Given a setting "duplicate_key" already exists
    When I build a setting with key "duplicate_key"
    Then the model should be invalid
    And there should be a validation error on "key"

  Scenario: Reading a missing key returns nil
    When I read the setting "does_not_exist"
    Then the result should be nil

  Scenario: Reading an existing key returns its value
    Given a setting "custom_dir" with value "/data/dl" exists
    When I read the setting "custom_dir"
    Then the result should be "/data/dl"

  Scenario: A symbol key reads the same value
    Given a setting "sym_key" with value "hello" exists
    When I read the setting with symbol key "sym_key"
    Then the result should be "hello"

  Scenario: Setting a new key creates it
    When I set the setting "brand_new" to "v1"
    Then the setting "brand_new" should equal "v1"

  Scenario: Setting an existing key updates it without duplicating
    Given a setting "existing_key" with value "old" exists
    When I set the setting "existing_key" to "new"
    Then the setting "existing_key" should equal "new"
    And there should be exactly 1 setting with key "existing_key"

  Scenario: Repeated upserts never duplicate
    When I set the setting "once_key" to "a"
    And I set the setting "once_key" to "b"
    And I set the setting "once_key" to "c"
    Then there should be exactly 1 setting with key "once_key"

  Scenario: A description can be stored on create
    When I set the setting "desc_key" to "val" with description "A description"
    Then the description of setting "desc_key" should be "A description"

  Scenario: Non-string values are coerced to strings
    When I set the setting "num_key" to the number 42
    Then the setting "num_key" should equal "42"

  Scenario: all_as_hash returns key to value pairs
    Given a setting "alpha" with value "1" exists
    And a setting "beta" with value "2" exists
    When I read the setting "alpha"
    Then the settings hash should include "alpha" mapped to "1"
    And the settings hash should include "beta" mapped to "2"
