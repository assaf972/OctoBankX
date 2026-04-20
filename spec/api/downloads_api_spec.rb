require_relative '../spec_helper'

RSpec.describe 'Downloads API' do
  let(:bank)    { create(:bank) }
  let(:account) { create(:account, bank: bank) }

  # ----------------------------------------------------------------
  # GET /api/v1/downloads
  # ----------------------------------------------------------------
  describe 'GET /api/v1/downloads' do
    it 'returns 200 with JSON' do
      get '/api/v1/downloads'
      expect(last_response.status).to eq 200
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns an empty array when no downloads exist' do
      get '/api/v1/downloads'
      expect(JSON.parse(last_response.body)).to eq []
    end

    it 'returns all downloads' do
      create(:download, account: account, bank: bank, status: 'success')
      create(:download, account: account, bank: bank, status: 'failed')
      get '/api/v1/downloads'
      expect(JSON.parse(last_response.body).size).to eq 2
    end

    it 'includes expected fields in each record' do
      create(:download, account: account, bank: bank)
      get '/api/v1/downloads'
      item = JSON.parse(last_response.body).first
      expect(item.keys).to include(
        'id', 'account_id', 'account_name', 'account_no',
        'bank_id', 'bank_name', 'date', 'status',
        'error_message', 'file_path', 'started_at',
        'completed_at', 'duration_s', 'created_at'
      )
    end

    it 'filters by status=pending' do
      create(:download, account: account, bank: bank, status: 'pending')
      create(:download, account: account, bank: bank, status: 'success')
      get '/api/v1/downloads', status: 'pending'
      body = JSON.parse(last_response.body)
      expect(body).to all(include('status' => 'pending'))
      expect(body.size).to eq 1
    end

    it 'filters by status=running' do
      create(:download, account: account, bank: bank, status: 'running')
      create(:download, account: account, bank: bank, status: 'failed')
      get '/api/v1/downloads', status: 'running'
      expect(JSON.parse(last_response.body)).to all(include('status' => 'running'))
    end

    it 'filters by status=success' do
      create(:download, account: account, bank: bank, status: 'success')
      create(:download, account: account, bank: bank, status: 'failed')
      get '/api/v1/downloads', status: 'success'
      expect(JSON.parse(last_response.body)).to all(include('status' => 'success'))
    end

    it 'filters by status=failed' do
      create(:download, account: account, bank: bank, status: 'failed')
      create(:download, account: account, bank: bank, status: 'success')
      get '/api/v1/downloads', status: 'failed'
      body = JSON.parse(last_response.body)
      expect(body).to all(include('status' => 'failed'))
      expect(body.size).to eq 1
    end

    it 'filters by account_id' do
      other_account = create(:account, bank: bank)
      create(:download, account: account,       bank: bank, status: 'success')
      create(:download, account: other_account, bank: bank, status: 'success')
      get '/api/v1/downloads', account_id: account.id.to_s
      body = JSON.parse(last_response.body)
      expect(body).to all(include('account_id' => account.id))
    end

    it 'filters by date' do
      create(:download, account: account, bank: bank, date: Date.today)
      create(:download, account: account, bank: bank, date: Date.today - 5)
      get '/api/v1/downloads', date: Date.today.to_s
      body = JSON.parse(last_response.body)
      expect(body).to all(include('date' => Date.today.to_s))
      expect(body.size).to eq 1
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/downloads/:id
  # ----------------------------------------------------------------
  describe 'GET /api/v1/downloads/:id' do
    it 'returns 200 with download data' do
      dl = create(:download, account: account, bank: bank)
      get "/api/v1/downloads/#{dl.id}"
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body['id']).to eq dl.id
    end

    it 'returns 404 for a missing id' do
      get '/api/v1/downloads/999999'
      expect(last_response.status).to eq 404
    end
  end

  # ----------------------------------------------------------------
  # POST /api/v1/downloads
  # ----------------------------------------------------------------
  describe 'POST /api/v1/downloads' do
    let(:payload) { { account_id: account.id, date: Date.today.to_s } }

    it 'creates a download and returns 201' do
      post_json '/api/v1/downloads', payload
      expect(last_response.status).to eq 201
    end

    it 'returns the new download record' do
      post_json '/api/v1/downloads', payload
      body = JSON.parse(last_response.body)
      expect(body['account_id']).to eq account.id
      expect(body['status']).to eq 'pending'
      expect(body['date']).to eq Date.today.to_s
    end

    it 'persists the download to the DB' do
      expect {
        post_json '/api/v1/downloads', payload
      }.to change { Download.count }.by(1)
    end

    it 'defaults date to today when not provided' do
      post_json '/api/v1/downloads', { account_id: account.id }
      body = JSON.parse(last_response.body)
      expect(body['date']).to eq Date.today.to_s
    end

    it 'returns 422 when account_id is missing' do
      post_json '/api/v1/downloads', {}
      expect(last_response.status).to eq 422
      expect(JSON.parse(last_response.body)['error']).to include('account_id')
    end

    it 'returns 404 when account does not exist' do
      post_json '/api/v1/downloads', { account_id: 999_999 }
      expect(last_response.status).to eq 404
    end

    it 'returns 409 when a download already exists for the same account+date' do
      create(:download, account: account, bank: bank, date: Date.today)
      post_json '/api/v1/downloads', payload
      expect(last_response.status).to eq 409
    end
  end

  # ----------------------------------------------------------------
  # PATCH /api/v1/downloads/:id/status
  # ----------------------------------------------------------------
  describe 'PATCH /api/v1/downloads/:id/status' do
    let!(:dl) { create(:download, account: account, bank: bank, status: 'pending') }

    it 'transitions to running' do
      patch_json "/api/v1/downloads/#{dl.id}/status", { status: 'running' }
      expect(last_response.status).to eq 200
      expect(JSON.parse(last_response.body)['status']).to eq 'running'
      expect(dl.reload.started_at).not_to be_nil
    end

    it 'transitions to success with file_path' do
      patch_json "/api/v1/downloads/#{dl.id}/status",
                 { status: 'success', file_path: '/data/stmt.csv' }
      body = JSON.parse(last_response.body)
      expect(body['status']).to eq 'success'
      expect(body['file_path']).to eq '/data/stmt.csv'
      expect(dl.reload.completed_at).not_to be_nil
    end

    it 'transitions to failed with error_message' do
      patch_json "/api/v1/downloads/#{dl.id}/status",
                 { status: 'failed', error_message: 'SFTP timeout' }
      body = JSON.parse(last_response.body)
      expect(body['status']).to eq 'failed'
      expect(body['error_message']).to eq 'SFTP timeout'
    end

    it 'returns 422 for an invalid status value' do
      patch_json "/api/v1/downloads/#{dl.id}/status", { status: 'unknown' }
      expect(last_response.status).to eq 422
    end

    it 'returns 404 for a missing download id' do
      patch_json '/api/v1/downloads/999999/status', { status: 'running' }
      expect(last_response.status).to eq 404
    end
  end
end
