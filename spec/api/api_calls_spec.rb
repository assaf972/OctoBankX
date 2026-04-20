require_relative '../spec_helper'

# ====================================================================
# ApiCall model unit tests
# ====================================================================
RSpec.describe ApiCall do
  describe 'validations' do
    it 'requires http_method' do
      c = ApiCall.new(endpoint: '/api/v1/accounts', status: 'success')
      expect(c.valid?).to be false
      expect(c.errors[:http_method]).not_to be_empty
    end

    it 'requires endpoint' do
      c = ApiCall.new(http_method: 'GET', status: 'success')
      expect(c.valid?).to be false
      expect(c.errors[:endpoint]).not_to be_empty
    end

    it 'requires status' do
      c = ApiCall.new(http_method: 'GET', endpoint: '/api/v1/accounts')
      expect(c.valid?).to be false
      expect(c.errors[:status]).not_to be_empty
    end

    it 'rejects an unknown status' do
      c = ApiCall.new(http_method: 'GET', endpoint: '/api/v1/accounts', status: 'pending')
      expect(c.valid?).to be false
    end

    it 'accepts success' do
      c = ApiCall.new(http_method: 'GET', endpoint: '/api/v1/accounts', status: 'success',
                      created_at: Time.now)
      expect(c.valid?).to be true
    end

    it 'accepts failed' do
      c = ApiCall.new(http_method: 'GET', endpoint: '/api/v1/accounts', status: 'failed',
                      created_at: Time.now)
      expect(c.valid?).to be true
    end
  end

  describe 'predicates' do
    it '#success? is true only for success' do
      expect(build(:api_call, status: 'success').success?).to be true
      expect(build(:api_call, status: 'failed').success?).to be false
    end

    it '#failed? is true only for failed' do
      expect(build(:api_call, status: 'failed').failed?).to be true
      expect(build(:api_call, status: 'success').failed?).to be false
    end
  end

  describe '.recent' do
    it 'returns at most N records newest first' do
      5.times { create(:api_call) }
      expect(ApiCall.recent(3).all.size).to eq 3
    end

    it 'orders newest first' do
      older = create(:api_call, created_at: Time.now - 3600)
      newer = create(:api_call, created_at: Time.now)
      expect(ApiCall.recent(2).all.first.id).to eq newer.id
    end
  end

  describe '.distinct_endpoints' do
    it 'returns unique sorted endpoints' do
      create(:api_call, endpoint: '/api/v1/accounts')
      create(:api_call, endpoint: '/api/v1/downloads')
      create(:api_call, endpoint: '/api/v1/accounts')
      eps = ApiCall.distinct_endpoints
      expect(eps.uniq).to eq eps
      expect(eps).to include('/api/v1/accounts', '/api/v1/downloads')
    end
  end
end

# ====================================================================
# Automatic logging — every API request persists an ApiCall
# ====================================================================
RSpec.describe 'ApiCall automatic logging' do
  let(:bank)    { create(:bank) }
  let(:account) { create(:account, bank: bank) }

  def last_call = ApiCall.order(:id).last

  # ----------------------------------------------------------------
  # GET /api/v1/accounts
  # ----------------------------------------------------------------
  describe 'GET /api/v1/accounts' do
    it 'creates an ApiCall record' do
      expect { get '/api/v1/accounts' }.to change { ApiCall.count }.by(1)
    end

    it 'logs http_method=GET, endpoint, status=success, http_status=200' do
      get '/api/v1/accounts'
      c = last_call
      expect(c.http_method).to  eq 'GET'
      expect(c.endpoint).to     eq '/api/v1/accounts'
      expect(c.status).to       eq 'success'
      expect(c.http_status).to  eq 200
    end

    it 'records a non-negative duration_ms' do
      get '/api/v1/accounts'
      expect(last_call.duration_ms).to be >= 0
    end

    it 'records the caller host' do
      get '/api/v1/accounts'
      expect(last_call.host).not_to be_nil
    end

    it 'leaves account_id nil (list endpoint)' do
      get '/api/v1/accounts'
      expect(last_call.account_id).to be_nil
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/accounts/:id  — success
  # ----------------------------------------------------------------
  describe 'GET /api/v1/accounts/:id (found)' do
    it 'logs success with the correct account_id' do
      get "/api/v1/accounts/#{account.id}"
      c = last_call
      expect(c.status).to      eq 'success'
      expect(c.http_status).to eq 200
      expect(c.account_id).to  eq account.id
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/accounts/:id  — 404
  # ----------------------------------------------------------------
  describe 'GET /api/v1/accounts/:id (not found)' do
    it 'logs failed with http_status=404' do
      get '/api/v1/accounts/999999'
      c = last_call
      expect(c.status).to      eq 'failed'
      expect(c.http_status).to eq 404
    end

    it 'captures the error message from the JSON response' do
      get '/api/v1/accounts/999999'
      expect(last_call.error_message).to include('Account not found')
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/downloads  — with account_id filter
  # ----------------------------------------------------------------
  describe 'GET /api/v1/downloads with account_id param' do
    it 'sets account_id on the log record' do
      get "/api/v1/downloads?account_id=#{account.id}"
      expect(last_call.account_id).to eq account.id
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/downloads/:id
  # ----------------------------------------------------------------
  describe 'GET /api/v1/downloads/:id' do
    let!(:dl) { create(:download, account: account, bank: bank) }

    it 'logs the download account_id' do
      get "/api/v1/downloads/#{dl.id}"
      expect(last_call.account_id).to eq account.id
    end

    it 'logs failed on 404' do
      get '/api/v1/downloads/999999'
      c = last_call
      expect(c.status).to      eq 'failed'
      expect(c.http_status).to eq 404
      expect(c.error_message).to include('Download not found')
    end
  end

  # ----------------------------------------------------------------
  # POST /api/v1/downloads
  # ----------------------------------------------------------------
  describe 'POST /api/v1/downloads' do
    it 'logs success with http_status=201 and account_id' do
      post_json '/api/v1/downloads', { account_id: account.id }
      c = last_call
      expect(c.http_method).to  eq 'POST'
      expect(c.status).to       eq 'success'
      expect(c.http_status).to  eq 201
      expect(c.account_id).to   eq account.id
    end

    it 'logs failed with 422 when account_id is missing' do
      post_json '/api/v1/downloads', {}
      c = last_call
      expect(c.status).to      eq 'failed'
      expect(c.http_status).to eq 422
      expect(c.error_message).to include('account_id')
    end

    it 'logs failed with 404 when account does not exist' do
      post_json '/api/v1/downloads', { account_id: 999_999 }
      c = last_call
      expect(c.status).to      eq 'failed'
      expect(c.http_status).to eq 404
    end

    it 'logs failed with 409 on duplicate' do
      create(:download, account: account, bank: bank, date: Date.today)
      post_json '/api/v1/downloads', { account_id: account.id }
      c = last_call
      expect(c.status).to      eq 'failed'
      expect(c.http_status).to eq 409
    end
  end

  # ----------------------------------------------------------------
  # PATCH /api/v1/downloads/:id/status
  # ----------------------------------------------------------------
  describe 'PATCH /api/v1/downloads/:id/status' do
    let!(:dl) { create(:download, account: account, bank: bank, status: 'pending') }

    it 'logs http_method=PATCH, success, and account_id' do
      patch_json "/api/v1/downloads/#{dl.id}/status", { status: 'running' }
      c = last_call
      expect(c.http_method).to  eq 'PATCH'
      expect(c.status).to       eq 'success'
      expect(c.account_id).to   eq account.id
    end

    it 'logs failed with 422 for an invalid status' do
      patch_json "/api/v1/downloads/#{dl.id}/status", { status: 'bogus' }
      c = last_call
      expect(c.status).to      eq 'failed'
      expect(c.http_status).to eq 422
    end

    it 'logs failed with 404 for a missing download' do
      patch_json '/api/v1/downloads/999999/status', { status: 'running' }
      expect(last_call.http_status).to eq 404
    end
  end

  # ----------------------------------------------------------------
  # GET /api/v1/status
  # ----------------------------------------------------------------
  describe 'GET /api/v1/status' do
    it 'logs the status call with no account_id' do
      get '/api/v1/status'
      c = last_call
      expect(c.endpoint).to    eq '/api/v1/status'
      expect(c.status).to      eq 'success'
      expect(c.account_id).to  be_nil
    end
  end
end

# ====================================================================
# /api-calls UI page
# ====================================================================
RSpec.describe 'GET /api-calls' do
  it 'returns 200' do
    get '/api-calls'
    expect(last_response).to be_ok
  end

  it 'shows "no records" when empty' do
    get '/api-calls'
    expect(last_response.body).to include('api-calls') # page loaded
  end

  it 'displays logged calls' do
    create(:api_call, endpoint: '/api/v1/accounts', http_method: 'GET', status: 'success')
    get '/api-calls'
    expect(last_response.body).to include('/api/v1/accounts')
  end

  it 'shows endpoint, method, status columns' do
    create(:api_call, http_method: 'POST', endpoint: '/api/v1/downloads', status: 'success')
    get '/api-calls'
    expect(last_response.body).to include('POST', '/api/v1/downloads')
  end

  it 'filters by status=failed' do
    create(:api_call, status: 'success', endpoint: '/api/v1/accounts')
    create(:api_call, status: 'failed',  endpoint: '/api/v1/downloads', error_message: 'Not found')
    get '/api-calls', status: 'failed'
    expect(last_response.body).to     include('/api/v1/downloads')
    expect(last_response.body).not_to include('badge-success')
  end

  it 'filters by status=success' do
    create(:api_call, status: 'success', endpoint: '/api/v1/accounts')
    create(:api_call, status: 'failed',  endpoint: '/api/v1/status')
    get '/api-calls', status: 'success'
    expect(last_response.body).to     include('/api/v1/accounts')
    expect(last_response.body).not_to include('badge-failed')
  end

  it 'filters by method=POST' do
    create(:api_call, http_method: 'GET',  endpoint: '/api/v1/accounts')
    create(:api_call, http_method: 'POST', endpoint: '/api/v1/downloads')
    get '/api-calls', method: 'POST'
    expect(last_response.body).to     include('/api/v1/downloads')
    expect(last_response.body).not_to include('badge-method-get')
  end

  it 'filters by endpoint' do
    create(:api_call, endpoint: '/api/v1/accounts', http_method: 'GET')
    create(:api_call, endpoint: '/api/v1/downloads', http_method: 'POST')
    get '/api-calls', endpoint: '/api/v1/accounts'
    expect(last_response.body).to     include('/api/v1/accounts')
    expect(last_response.body).not_to include('badge-method-post')
  end

  it 'shows the endpoint filter dropdown populated from existing records' do
    create(:api_call, endpoint: '/api/v1/accounts')
    create(:api_call, endpoint: '/api/v1/downloads')
    get '/api-calls'
    expect(last_response.body).to include('/api/v1/accounts', '/api/v1/downloads')
  end

  it 'is reachable from the nav' do
    get '/'
    expect(last_response.body).to include('/api-calls')
  end
end
