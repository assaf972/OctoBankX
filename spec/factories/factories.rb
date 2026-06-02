FactoryBot.define do
  factory :bank do
    sequence(:name)      { |n| "Bank #{n}" }
    sequence(:sftp_host) { |n| "sftp#{n}.bank.test" }
    sftp_port            { 22 }
    sftp_remote_path     { '/statements' }
    created_at           { Time.now }
    updated_at           { Time.now }
  end

  factory :download do
    association :bank
    date       { Date.today }
    status     { 'pending' }
    created_at { Time.now }
  end

  factory :email_sender do
    association :bank
    sequence(:sender_name)  { |n| "Sender #{n}" }
    sequence(:sender_email) { |n| "sender#{n}@bank.test" }
    active                  { true }
    created_at              { Time.now }
    updated_at              { Time.now }
  end

  factory :setting do
    sequence(:key)   { |n| "setting_key_#{n}" }
    value            { 'default_value' }
    description      { 'A test setting' }
    updated_at       { Time.now }
  end
end
