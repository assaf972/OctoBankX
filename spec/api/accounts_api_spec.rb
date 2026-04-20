require_relative '../spec_helper'

RSpec.describe 'Accounts API' do
  let(:bank)    { create(:bank) }
  let(:account) { create(:account, bank: bank, name: 'Main Account', account_no: 'ACC001', currency: 'USD') }

  # ----------------------------------------------------------------
  # GET /api/v1/accounts
  # ----------------------------------------------------------------
  describe 'GET /api/v1/accounts' do
    it 'returns 200 with JSON content-type' do
      get '/api/v1/accounts'
      expect(last_response.status).to eq 200
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns an empty array when no accounts exist' do
      get '/api/v1/accounts'
      expect(JSON.parse(last_response.body)).to eq []
    end

    it 'returns all accounts' do
      account
      create(:account, bank: bank, name: 'Second Account')
      get '/api/v1/accounts'
      body = JSON.parse(last_response.body)
      expect(body.size).to eq 2
    end

    it 'includes expected fields' do
      account
      get '/api/v1/accounts'
      item = JSON.parse(last_response.body).first
      expect(item.keys).to include('id', 'name', 'account_no', 'bank_id', 'bank_name',
                                   'branch', 'currency', 'balance', 'balance_date')
    end

    it 'embeds bank_name in each account' do
      account
      get '/api/v1/accounts'
      item = JSON.parse(last_response.body).first
      expect(item['bank_name']).to eq bank.name
    end

    it 'returns accounts sorted by name' do
      create(:account, bank: bank, name: 'Zebra Corp')
      create(:account, bank: bank, name: 'Alpha Ltd')
      get '/api/v1/accounts'
      names = JSON.parse(last_response.body).map { |a| a['name'] }
      expect(names).to eq names.sort
    end

    it 'does not expose sftp_password' do
      account
      get '/api/v1/accounts'
      item = JSON.parse(last_response.body).first
      expect(item.keys).not_to include('sftp_password')
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/accounts/:id
  # ----------------------------------------------------------------
  describe 'GET /api/v1/accounts/:id' do
    it 'returns 200 with correct account data' do
      get "/api/v1/accounts/#{account.id}"
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body['id']).to eq account.id
      expect(body['account_no']).to eq 'ACC001'
    end

    it 'includes created_at and updated_at' do
      get "/api/v1/accounts/#{account.id}"
      body = JSON.parse(last_response.body)
      expect(body.keys).to include('created_at', 'updated_at')
    end

    it 'returns 404 for a non-existent account' do
      get '/api/v1/accounts/999999'
      expect(last_response.status).to eq 404
      body = JSON.parse(last_response.body)
      expect(body['error']).to include('Account not found')
    end

    it 'returns 404 for id=0' do
      get '/api/v1/accounts/0'
      expect(last_response.status).to eq 404
    end
  end
end
