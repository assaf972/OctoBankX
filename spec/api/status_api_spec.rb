require_relative '../spec_helper'

RSpec.describe 'Status API' do
  # ----------------------------------------------------------------
  # GET /api/v1/status
  # ----------------------------------------------------------------
  describe 'GET /api/v1/status' do
    it 'returns 200 with JSON' do
      get '/api/v1/status'
      expect(last_response.status).to eq 200
      expect(last_response.content_type).to include('application/json')
    end

    it 'includes top-level status=ok' do
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['status']).to eq 'ok'
    end

    it 'includes a timestamp' do
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['timestamp']).not_to be_nil
      expect { Time.parse(body['timestamp']) }.not_to raise_error
    end

    it 'returns accounts_count and banks_count' do
      bank    = create(:bank)
      _acct   = create(:account, bank: bank)
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['accounts_count']).to eq 1
      expect(body['banks_count']).to eq 1
    end

    it 'includes totals for all four statuses' do
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['totals'].keys).to match_array(%w[pending running success failed])
    end

    it 'counts total downloads correctly by status' do
      bank    = create(:bank)
      account = create(:account, bank: bank)
      create(:download, account: account, bank: bank, status: 'success')
      create(:download, account: account, bank: bank, status: 'success')
      create(:download, account: account, bank: bank, status: 'failed')
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['totals']['success']).to eq 2
      expect(body['totals']['failed']).to  eq 1
      expect(body['totals']['pending']).to eq 0
    end

    it 'includes today counts scoped to current date' do
      bank    = create(:bank)
      account = create(:account, bank: bank)
      create(:download, account: account, bank: bank, status: 'success', date: Date.today)
      create(:download, account: account, bank: bank, status: 'success', date: Date.today - 1)
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['today']['success']).to eq 1
      expect(body['today']['date']).to eq Date.today.to_s
    end

    it 'reports last_success as nil when no successful downloads exist' do
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['last_success']).to be_nil
    end

    it 'reports last_failure as nil when no failed downloads exist' do
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['last_failure']).to be_nil
    end

    it 'populates last_success with the most recent successful download' do
      bank    = create(:bank)
      account = create(:account, bank: bank)
      dl = create(:download, account: account, bank: bank, status: 'success',
                  completed_at: Time.now)
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['last_success']['id']).to eq dl.id
      expect(body['last_success']['completed_at']).not_to be_nil
    end

    it 'populates last_failure with error_message' do
      bank    = create(:bank)
      account = create(:account, bank: bank)
      dl = create(:download, account: account, bank: bank, status: 'failed',
                  error_message: 'Host unreachable', completed_at: Time.now)
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['last_failure']['error_message']).to eq 'Host unreachable'
      expect(body['last_failure']['id']).to eq dl.id
    end

    it 'returns zero counts when no downloads exist' do
      get '/api/v1/status'
      body = JSON.parse(last_response.body)
      expect(body['totals'].values.sum).to eq 0
    end
  end
end
