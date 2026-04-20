require 'rack/test'
require 'rspec'
require 'factory_bot'

ENV['RACK_ENV'] = 'test'

# Use a per-process temp file so no URI safeguard issues
TEST_DB_PATH = "/tmp/octobankx_test_#{Process.pid}.db" unless defined?(TEST_DB_PATH)
ENV['DATABASE_URL'] = "sqlite:///#{TEST_DB_PATH}"

require_relative '../db/database'
OctoBankX.migrate!

require_relative '../models/bank'
require_relative '../models/account'
require_relative '../models/download'
require_relative '../models/setting'
require_relative '../models/api_call'
require_relative '../app'

Dir[File.join(__dir__, 'factories/**/*.rb')].each { |f| require f }

FactoryBot.define do
  to_create { |instance| instance.save(raise_on_failure: true) }
end

DB = OctoBankX.db

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include FactoryBot::Syntax::Methods

  config.around(:each) do |example|
    DB.transaction(rollback: :always, auto_savepoint: true) { example.run }
  end

  config.after(:suite) do
    File.delete(TEST_DB_PATH) if File.exist?(TEST_DB_PATH)
  end

  config.expect_with(:rspec) { |c| c.syntax = :expect }

  def app
    OctoBankXApp
  end

  # Convenience helpers for JSON API requests
  def post_json(path, payload = {})
    post path, payload.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  def patch_json(path, payload = {})
    patch path, payload.to_json, 'CONTENT_TYPE' => 'application/json'
  end
end
