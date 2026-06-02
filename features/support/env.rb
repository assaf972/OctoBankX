# Cucumber test environment for OctoBankX.
# Mirrors spec/spec_helper.rb: uses a throwaway SQLite DB, runs migrations,
# loads the Sinatra app, and isolates each scenario in a transaction.

require 'capybara/cucumber'
require 'rack/test'
require 'factory_bot'
require 'database_cleaner/sequel'
require 'rspec/mocks'
require 'json'
require 'tmpdir'

ENV['RACK_ENV'] = 'test'

# Per-process temp DB so runs never touch the real octobankx.db
TEST_DB_PATH = "/tmp/octobankx_cucumber_#{Process.pid}.db" unless defined?(TEST_DB_PATH)
ENV['DATABASE_URL'] = "sqlite:///#{TEST_DB_PATH}"

require_relative '../../db/database'
OctoBankX.migrate!

require_relative '../../models/bank'
require_relative '../../models/download'
require_relative '../../models/setting'
require_relative '../../models/email_sender'
require_relative '../../models/log_event'
require_relative '../../app'

# Quiet the job/helper stdout loggers so Cucumber output stays readable.
require_relative '../../jobs/download_job'
require_relative '../../helpers/sftp_helper'
DownloadJob::LOG.level = Logger::FATAL
SftpHelper::LOG.level  = Logger::FATAL

# Load factories (shared with the RSpec suite)
Dir[File.expand_path('../../../spec/factories/**/*.rb', __FILE__)].each { |f| require f }
FactoryBot.define { to_create { |instance| instance.save(raise_on_failure: true) } }
World(FactoryBot::Syntax::Methods)

# Drive the Sinatra app in-process — no real browser/server needed.
Capybara.app             = OctoBankXApp
Capybara.default_driver  = :rack_test

# Per-scenario isolation via a rolled-back transaction (same as RSpec).
DatabaseCleaner[:sequel].db       = OctoBankX.db
DatabaseCleaner[:sequel].strategy = :transaction

# rspec-mocks inside Cucumber — used to stub SFTP / IMAP / POP3 in unit-style
# scenarios ported from the RSpec suite (allow/expect(...).to receive, doubles).
World(RSpec::Mocks::ExampleMethods)

# Rack::Test for the JSON API steps — supports GET/POST/PATCH with raw bodies.
World(Rack::Test::Methods)
module RackTestApp
  def app
    OctoBankXApp
  end
end
World(RackTestApp)

Before do
  DatabaseCleaner[:sequel].start
  RSpec::Mocks.setup
end

After do
  begin
    RSpec::Mocks.verify
  ensure
    RSpec::Mocks.teardown
    DatabaseCleaner[:sequel].clean
  end
end

at_exit { File.delete(TEST_DB_PATH) if File.exist?(TEST_DB_PATH) }
