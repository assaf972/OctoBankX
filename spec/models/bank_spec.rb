require_relative '../spec_helper'

RSpec.describe Bank do
  # ----------------------------------------------------------------
  # Validations
  # ----------------------------------------------------------------
  describe 'validations' do
    it 'requires name' do
      b = Bank.new(sftp_host: 'sftp.bank.com', sftp_port: 22)
      expect(b.valid?).to be false
      expect(b.errors[:name]).not_to be_empty
    end

    it 'requires sftp_host' do
      b = Bank.new(name: 'My Bank', sftp_port: 22)
      expect(b.valid?).to be false
      expect(b.errors[:sftp_host]).not_to be_empty
    end

    it 'requires name to be unique' do
      create(:bank, name: 'Unique Bank')
      b = Bank.new(name: 'Unique Bank', sftp_host: 'x.com', sftp_port: 22)
      expect(b.valid?).to be false
      expect(b.errors[:name]).not_to be_empty
    end

    it 'allows two banks on the same sftp_host with different names' do
      create(:bank, name: 'Bank A', sftp_host: 'shared.sftp.com')
      b = Bank.new(name: 'Bank B', sftp_host: 'shared.sftp.com', sftp_port: 22,
                   sftp_remote_path: '/', created_at: Time.now, updated_at: Time.now)
      expect(b.valid?).to be true
    end

    it 'requires sftp_port to be >= 1' do
      b = Bank.new(name: 'X', sftp_host: 'h.com', sftp_port: 0,
                   sftp_remote_path: '/', created_at: Time.now, updated_at: Time.now)
      expect(b.valid?).to be false
    end

    it 'requires sftp_port to be <= 65535' do
      b = Bank.new(name: 'X', sftp_host: 'h.com', sftp_port: 70000,
                   sftp_remote_path: '/', created_at: Time.now, updated_at: Time.now)
      expect(b.valid?).to be false
    end

    it 'is valid with all required attributes' do
      expect(build(:bank).valid?).to be true
    end

    it 'defaults sftp_port to 22' do
      bank = create(:bank)
      expect(bank.sftp_port).to eq 22
    end
  end

  # ----------------------------------------------------------------
  # #sftp_url
  # ----------------------------------------------------------------
  describe '#sftp_url' do
    it 'builds a well-formed sftp URL' do
      b = build(:bank, sftp_host: 'sftp.bank.com', sftp_port: 22, sftp_remote_path: '/statements')
      expect(b.sftp_url).to eq 'sftp://sftp.bank.com:22/statements'
    end

    it 'includes a non-standard port in the URL' do
      b = build(:bank, sftp_host: 'sftp.bank.com', sftp_port: 2222, sftp_remote_path: '/data')
      expect(b.sftp_url).to eq 'sftp://sftp.bank.com:2222/data'
    end
  end

  # ----------------------------------------------------------------
  # Associations
  # ----------------------------------------------------------------
  describe 'associations' do
    it 'has many accounts' do
      bank    = create(:bank)
      account = create(:account, bank: bank)
      expect(bank.accounts).to include(account)
    end

    it 'has many downloads' do
      bank     = create(:bank)
      account  = create(:account, bank: bank)
      download = create(:download, bank: bank, account: account)
      expect(bank.downloads).to include(download)
    end

    it 'counts zero accounts for a new bank' do
      bank = create(:bank)
      expect(bank.accounts_dataset.count).to eq 0
    end

    it 'counts multiple accounts correctly' do
      bank = create(:bank)
      3.times { create(:account, bank: bank) }
      expect(bank.accounts_dataset.count).to eq 3
    end
  end

  # ----------------------------------------------------------------
  # UI routes
  # ----------------------------------------------------------------
  describe 'GET /banks' do
    it 'returns 200' do
      get '/banks'
      expect(last_response).to be_ok
    end

    it 'lists all banks' do
      create(:bank, name: 'First National')
      create(:bank, name: 'Second Federal')
      get '/banks'
      expect(last_response.body).to include('First National', 'Second Federal')
    end

    it 'shows an empty state when no banks exist' do
      get '/banks'
      expect(last_response.body).to include('No banks')
    end
  end

  describe 'POST /banks' do
    let(:valid_params) do
      { name: 'Test Bank', sftp_host: 'sftp.test.com', sftp_port: '22', sftp_remote_path: '/stmts' }
    end

    it 'creates a new bank' do
      expect { post '/banks', valid_params }.to change { Bank.count }.by(1)
    end

    it 'persists all supplied fields' do
      post '/banks', valid_params
      b = Bank.first(name: 'Test Bank')
      expect(b.sftp_host).to eq 'sftp.test.com'
      expect(b.sftp_port).to eq 22
      expect(b.sftp_remote_path).to eq '/stmts'
    end

    it 'redirects to /banks on success' do
      post '/banks', valid_params
      expect(last_response).to be_redirect
      follow_redirect!
      expect(last_request.path).to eq '/banks'
    end

    it 'shows a success flash message' do
      post '/banks', valid_params
      follow_redirect!
      expect(last_response.body).to include('Test Bank')
    end

    it 'does not create a bank when name is missing' do
      expect {
        post '/banks', sftp_host: 'sftp.test.com', sftp_port: '22', sftp_remote_path: '/'
      }.not_to change { Bank.count }
    end

    it 'shows an error flash when name is duplicate' do
      create(:bank, name: 'Existing Bank')
      post '/banks', name: 'Existing Bank', sftp_host: 'sftp.x.com', sftp_port: '22', sftp_remote_path: '/'
      follow_redirect!
      expect(last_response.body).to include('Failed')
    end

    it 'does not create a bank when sftp_host is missing' do
      expect {
        post '/banks', name: 'No Host Bank', sftp_port: '22', sftp_remote_path: '/'
      }.not_to change { Bank.count }
    end
  end
end
