# Steps for model-level (unit) behavior ported from the RSpec model specs.
# A scenario builds/acts on @subject and asserts validity, errors, or results.

# --- Generic model assertions --------------------------------------

Then('the model should be valid') do
  expect(@subject.valid?).to be(true), -> { @subject.errors.full_messages.join(', ') }
end

Then('the model should be invalid') do
  expect(@subject.valid?).to be false
end

Then('there should be a validation error on {string}') do |field|
  @subject.valid?
  expect(@subject.errors[field.to_sym]).not_to be_empty
end

Then('the result should be {string}') do |value|
  expect(@result.to_s).to eq value
end

Then('the result should be nil') do
  expect(@result).to be_nil
end

# --- Bank model ----------------------------------------------------

When('I build a bank with:') do |table|
  attrs = table.rows_hash.transform_keys(&:to_sym)
  attrs[:sftp_port] = attrs[:sftp_port].to_i if attrs.key?(:sftp_port)
  @subject = Bank.new(attrs.merge(created_at: Time.now, updated_at: Time.now))
end

Then('the bank sftp url should be {string}') do |url|
  expect(@subject.sftp_url).to eq url
end

Then('a bank created with the standard details has port {int}') do |port|
  expect(find_or_create_bank('Default Port Bank').sftp_port).to eq port
end

# --- EmailSender model ---------------------------------------------

When('I build an email sender with:') do |table|
  attrs = table.rows_hash.transform_keys(&:to_sym)
  attrs[:active] = (attrs[:active] == 'true') if attrs.key?(:active)
  @subject = EmailSender.new(attrs)
end

Given('an active email sender {string} exists') do |email|
  EmailSender.create(sender_name: email.split('@').first, sender_email: email,
                     bank_id: find_or_create_bank('Default Bank').id, active: true,
                     created_at: Time.now, updated_at: Time.now)
end

Given('an inactive email sender {string} exists') do |email|
  EmailSender.create(sender_name: email.split('@').first, sender_email: email,
                     bank_id: find_or_create_bank('Default Bank').id, active: false,
                     created_at: Time.now, updated_at: Time.now)
end

Then('the email sender should be active') do
  expect(@subject.active?).to be true
end

Then('the email sender should be inactive') do
  expect(@subject.active?).to be false
end

When('I create an email sender {string} without explicit timestamps') do |email|
  @subject = EmailSender.create(sender_name: 'Stamp', sender_email: email,
                                bank_id: find_or_create_bank('Default Bank').id, active: true)
end

Then('the created email sender has both timestamps set') do
  expect(@subject.created_at).not_to be_nil
  expect(@subject.updated_at).not_to be_nil
end

When('I read the active email senders') do
  @result_list = EmailSender.active.all
end

Then('the active email sender count should be {int}') do |count|
  expect(@result_list.size).to eq count
end

Then('the active email senders should be {string}') do |emails|
  expected = emails.split(',').map(&:strip)
  expect(@result_list.map(&:sender_email)).to match_array(expected)
end

# --- Setting model -------------------------------------------------

When('I build a setting with no key') do
  @subject = Setting.new(value: 'foo')
end

When('I build a setting with key {string}') do |key|
  @subject = Setting.new(key: key, value: 'x')
end

When('I read the setting {string}') do |key|
  @result = Setting[key]
end

When('I read the setting with symbol key {string}') do |key|
  @result = Setting[key.to_sym]
end

When('I set the setting {string} to {string}') do |key, value|
  Setting.set(key, value)
end

When('I set the setting {string} to the number {int}') do |key, value|
  Setting.set(key, value)
end

When('I set the setting {string} to {string} with description {string}') do |key, value, desc|
  Setting.set(key, value, description: desc)
end

Then('the setting {string} should equal {string}') do |key, value|
  expect(Setting[key]).to eq value
end

Then('there should be exactly {int} setting with key {string}') do |count, key|
  expect(Setting.where(key: key).count).to eq count
end

Then('the description of setting {string} should be {string}') do |key, desc|
  expect(Setting.find(key: key).description).to eq desc
end

Then('the settings hash should include {string} mapped to {string}') do |key, value|
  expect(Setting.all_as_hash).to include(key => value)
end

# --- Build a candidate model invalid because of uniqueness ---------

Given('a setting {string} already exists') do |key|
  Setting.set(key, 'preexisting')
end
