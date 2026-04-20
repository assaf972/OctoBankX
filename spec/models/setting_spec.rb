require_relative '../spec_helper'

RSpec.describe Setting do
  # ----------------------------------------------------------------
  # Validations
  # ----------------------------------------------------------------
  describe 'validations' do
    it 'requires a key' do
      s = Setting.new(value: 'foo')
      expect(s.valid?).to be false
      expect(s.errors[:key]).not_to be_empty
    end

    it 'requires key to be unique' do
      create(:setting, key: 'duplicate_key')
      s = Setting.new(key: 'duplicate_key', value: 'x')
      expect(s.valid?).to be false
      expect(s.errors[:key]).not_to be_empty
    end

    it 'is valid with key and value' do
      expect(Setting.new(key: 'my_key', value: 'my_val', updated_at: Time.now).valid?).to be true
    end

    it 'is valid when value is blank' do
      expect(Setting.new(key: 'empty_val', value: '', updated_at: Time.now).valid?).to be true
    end
  end

  # ----------------------------------------------------------------
  # .[]  — read by key
  # ----------------------------------------------------------------
  describe '.[]' do
    it 'returns the value for an existing key' do
      create(:setting, key: 'custom_dir', value: '/data/dl')
      expect(Setting['custom_dir']).to eq '/data/dl'
    end

    it 'returns nil for a missing key' do
      expect(Setting['does_not_exist']).to be_nil
    end

    it 'accepts a symbol key' do
      create(:setting, key: 'sym_key', value: 'hello')
      expect(Setting[:sym_key]).to eq 'hello'
    end
  end

  # ----------------------------------------------------------------
  # .set  — upsert
  # ----------------------------------------------------------------
  describe '.set' do
    it 'creates a new setting when the key does not exist' do
      expect { Setting.set('brand_new', 'v1') }.to change { Setting.count }.by(1)
      expect(Setting['brand_new']).to eq 'v1'
    end

    it 'updates the value when the key already exists' do
      create(:setting, key: 'existing_key', value: 'old_value')
      Setting.set('existing_key', 'new_value')
      expect(Setting['existing_key']).to eq 'new_value'
      expect(Setting.where(key: 'existing_key').count).to eq 1
    end

    it 'does not create duplicates on repeated upserts' do
      3.times { Setting.set('once_key', rand.to_s) }
      expect(Setting.where(key: 'once_key').count).to eq 1
    end

    it 'stores an optional description on create' do
      Setting.set('desc_key', 'val', description: 'A description')
      expect(Setting.find(key: 'desc_key').description).to eq 'A description'
    end

    it 'coerces non-string values to strings' do
      Setting.set('num_key', 42)
      expect(Setting['num_key']).to eq '42'
    end
  end

  # ----------------------------------------------------------------
  # .all_as_hash
  # ----------------------------------------------------------------
  describe '.all_as_hash' do
    it 'returns all settings as a key=>value hash' do
      create(:setting, key: 'alpha', value: '1')
      create(:setting, key: 'beta',  value: '2')
      hash = Setting.all_as_hash
      expect(hash).to include('alpha' => '1', 'beta' => '2')
    end

    it 'returns an empty hash when no settings exist' do
      Setting.where { id > 0 }.delete  # wipe seeded rows for this test
      expect(Setting.all_as_hash).to eq({})
    end
  end

  # ----------------------------------------------------------------
  # UI routes
  # ----------------------------------------------------------------
  describe 'GET /settings' do
    it 'returns 200' do
      get '/settings'
      expect(last_response).to be_ok
    end

    it 'renders the seeded sftp_timeout key' do
      get '/settings'
      expect(last_response.body).to include('sftp_timeout')
    end

    it 'renders the seeded download_dir key' do
      get '/settings'
      expect(last_response.body).to include('download_dir')
    end

    it 'renders input fields for every setting' do
      count = Setting.count
      get '/settings'
      expect(last_response.body.scan('<input').size).to be >= count
    end
  end

  describe 'POST /settings' do
    it 'saves an updated value and redirects' do
      post '/settings', { 'settings[sftp_timeout]' => '90' }
      expect(last_response).to be_redirect
      follow_redirect!
      expect(Setting['sftp_timeout']).to eq '90'
    end

    it 'can update multiple settings in one request' do
      post '/settings', {
        'settings[sftp_timeout]'  => '45',
        'settings[retention_days]' => '180'
      }
      follow_redirect!
      expect(Setting['sftp_timeout']).to eq '45'
      expect(Setting['retention_days']).to eq '180'
    end

    it 'creates a new setting if the key is unknown' do
      expect {
        post '/settings', { 'settings[brand_new_setting]' => 'xyz' }
      }.to change { Setting.count }.by(1)
      expect(Setting['brand_new_setting']).to eq 'xyz'
    end

    it 'shows a success flash after saving' do
      post '/settings', { 'settings[sftp_timeout]' => '10' }
      follow_redirect!
      expect(last_response.body).to include('Settings saved')
    end
  end
end
