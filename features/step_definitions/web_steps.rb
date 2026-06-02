# Steps for driving the HTML web UI via Capybara (rack_test driver).

Given('a bank named {string} exists') do |name|
  Bank.create(
    name:             name,
    sftp_host:        'sftp.example.test',
    sftp_port:        22,
    sftp_remote_path: '/statements',
    created_at:       Time.now,
    updated_at:       Time.now
  )
end

Given('I am on the {string} page') do |path|
  visit path
end

When('I visit {string}') do |path|
  visit path
end

When('I fill in {string} with {string}') do |field, value|
  fill_in field, with: value
end

When('I press {string}') do |label|
  click_button label
end

# The bank form's submit button label is translated, so target it by selector.
When('I submit the bank form') do
  find('form[action="/banks"] button[type="submit"]').click
end

Then('I should see {string}') do |text|
  expect(page).to have_content(text)
end

Then('I should not see {string}') do |text|
  expect(page).to have_no_content(text)
end
