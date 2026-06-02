# Steps for the LogEvent model and the global exception-logging behavior.

# --- Model building / recording ------------------------------------

When('I build a log event with:') do |table|
  @subject = LogEvent.new(table.rows_hash.transform_keys(&:to_sym))
end

When('I record a {string} event with message {string}') do |kind, message|
  @event = LogEvent.public_send(kind, message)
end

When('I record an exception event with message {string}') do |message|
  raise 'underlying failure'
rescue StandardError => e
  @event = LogEvent.exception(e, message: message)
end

When('I record an exception event without a message') do
  raise ArgumentError, 'bad argument'
rescue StandardError => e
  @event = LogEvent.exception(e)
end

Given('a download exists') do
  @download = Download.create(bank_id: find_or_create_bank('LogBank').id,
                              date: Date.today, status: 'pending', created_at: Time.now)
end

When('I record a log event linked to that download') do
  @event = LogEvent.log('Linked message', download: @download)
end

# --- Model assertions ----------------------------------------------

Then('the log event kind should be {string}') do |kind|
  expect(@event.kind).to eq kind
end

Then('the log event message should include {string}') do |text|
  expect(@event.message).to include text
end

Then('the log event error class should be {string}') do |klass|
  expect(@event.error_class).to eq klass
end

Then('the log event should have a backtrace') do
  expect(@event.backtrace.to_s).not_to be_empty
end

Then('the log event should belong to that download') do
  expect(@event.download_id).to eq @download.id
  expect(@event.download).to eq @download
end

# --- Integration: exception logging --------------------------------

Given('the dashboard will raise when loaded') do
  allow(Download).to receive(:recent).and_raise(StandardError.new('dashboard boom'))
end

Then('an exception log event should be linked to the download for bank {string}') do |name|
  bank   = Bank.find(name: name)
  dl     = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  events = LogEvent.where(download_id: dl.id, kind: 'exception').all
  expect(events).not_to be_empty
  expect(events.first.backtrace.to_s).not_to be_empty
end

Then('an exception log event should exist with message containing {string}') do |text|
  events = LogEvent.where(kind: 'exception').all
  expect(events.map(&:message)).to include(a_string_including(text))
end
