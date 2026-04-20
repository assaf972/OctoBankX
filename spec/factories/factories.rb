FactoryBot.define do
  factory :bank do
    sequence(:name)      { |n| "Bank #{n}" }
    sequence(:sftp_host) { |n| "sftp#{n}.bank.test" }
    sftp_port            { 22 }
    sftp_remote_path     { '/statements' }
    created_at           { Time.now }
    updated_at           { Time.now }
  end

  factory :account do
    association :bank
    sequence(:name)       { |n| "Account #{n}" }
    sequence(:account_no) { |n| "ACC#{n.to_s.rjust(6, '0')}" }
    branch                { 'Main Branch' }
    currency              { 'USD' }
    balance               { 1000.0 }
    balance_date          { Date.today }
    sftp_username         { 'sftpuser' }
    sftp_password         { 'sftppass' }
    created_at            { Time.now }
    updated_at            { Time.now }
  end

  factory :download do
    association :account
    association :bank
    date       { Date.today }
    status     { 'pending' }
    created_at { Time.now }
  end

  factory :setting do
    sequence(:key)   { |n| "setting_key_#{n}" }
    value            { 'default_value' }
    description      { 'A test setting' }
    updated_at       { Time.now }
  end

  factory :api_call do
    http_method { 'GET' }
    endpoint      { '/api/v1/accounts' }
    host          { '127.0.0.1' }
    account_id    { nil }
    status        { 'success' }
    http_status   { 200 }
    duration_ms   { 42 }
    error_message { nil }
    created_at    { Time.now }
  end
end
