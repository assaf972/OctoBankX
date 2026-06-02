# Richer UI steps: dropdowns, flash/badge assertions, per-row actions,
# and data setup that avoids the (currently broken) Account model.

# --- Data setup -----------------------------------------------------

Given('a download for bank {string} with status {string} exists') do |bank_name, status|
  bank = Bank.find(name: bank_name) || Bank.create(
    name:             bank_name,
    sftp_host:        'sftp.example.test',
    sftp_port:        22,
    sftp_remote_path: '/statements',
    created_at:       Time.now,
    updated_at:       Time.now
  )
  Download.create(
    bank_id:    bank.id,
    date:       Date.today,
    status:     status,
    created_at: Time.now
  )
end

Given('an email sender {string} for bank {string} exists') do |email, bank_name|
  bank = Bank.find(name: bank_name) || Bank.create(
    name:             bank_name,
    sftp_host:        'sftp.example.test',
    sftp_port:        22,
    sftp_remote_path: '/statements',
    created_at:       Time.now,
    updated_at:       Time.now
  )
  EmailSender.create(
    sender_name:  email.split('@').first,
    sender_email: email,
    bank_id:      bank.id,
    active:       true,
    created_at:   Time.now,
    updated_at:   Time.now
  )
end

Given('a setting {string} with value {string} exists') do |key, value|
  Setting.set(key, value)
end

# --- Form interaction ----------------------------------------------

When('I select {string} from {string}') do |value, field|
  select value, from: field
end

# --- Per-row actions (scoped by the visible email so multiple rows are fine) ---

When('I deactivate the email sender {string}') do |email|
  find('tr', text: email).find("form[action$='/toggle'] button").click
end

When('I delete the email sender {string}') do |email|
  find('tr', text: email).find("form[action$='/delete'] button").click
end

# --- Assertions -----------------------------------------------------

Then('I should see a {string} flash message') do |type|
  expect(page).to have_css("div.flash.flash-#{type}")
end

Then('I should see a {string} status badge') do |status|
  expect(page).to have_css("span.badge.badge-#{status}")
end
