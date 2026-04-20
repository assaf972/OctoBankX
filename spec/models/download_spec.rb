require_relative '../spec_helper'

RSpec.describe Download do
  # ----------------------------------------------------------------
  # Validations
  # ----------------------------------------------------------------
  describe 'validations' do
    it 'requires account_id, bank_id, and date' do
      d = Download.new(status: 'pending')
      expect(d.valid?).to be false
      expect(d.errors[:account_id]).not_to be_empty
      expect(d.errors[:bank_id]).not_to be_empty
      expect(d.errors[:date]).not_to be_empty
    end

    it 'rejects an invalid status' do
      account = create(:account)
      d = Download.new(account_id: account.id, bank_id: account.bank_id,
                       date: Date.today, status: 'bogus')
      expect(d.valid?).to be false
      expect(d.errors[:status]).not_to be_empty
    end

    it 'accepts all valid statuses' do
      account = create(:account)
      %w[pending running success failed].each do |st|
        d = Download.new(account_id: account.id, bank_id: account.bank_id,
                         date: Date.today, status: st)
        expect(d.valid?).to(be(true)) { "expected status '#{st}' to be valid" }
      end
    end
  end

  # ----------------------------------------------------------------
  # Status predicates — tested without DB (no PK needed)
  # ----------------------------------------------------------------
  describe 'status predicates' do
    def dl(status) = Download.new(status: status, account_id: 1, bank_id: 1, date: Date.today)

    it '#pending? is true only for pending' do
      expect(dl('pending').pending?).to be true
      expect(dl('running').pending?).to be false
    end

    it '#running? is true only for running' do
      expect(dl('running').running?).to be true
      expect(dl('pending').running?).to be false
    end

    it '#success? is true only for success' do
      expect(dl('success').success?).to be true
      expect(dl('failed').success?).to be false
    end

    it '#failed? is true only for failed' do
      expect(dl('failed').failed?).to be true
      expect(dl('success').failed?).to be false
    end

    it 'only one predicate is true at a time' do
      %w[pending running success failed].each do |st|
        d     = dl(st)
        trues = %i[pending? running? success? failed?].count { |m| d.public_send(m) }
        expect(trues).to(eq(1)) { "#{st}: expected exactly 1 true predicate" }
      end
    end
  end

  # ----------------------------------------------------------------
  # Status-based filtering
  # ----------------------------------------------------------------
  describe 'filtering by status' do
    let(:account) { create(:account) }

    before do
      create(:download, account: account, bank: account.bank, status: 'pending')
      create(:download, account: account, bank: account.bank, status: 'running')
      create(:download, account: account, bank: account.bank, status: 'success')
      create(:download, account: account, bank: account.bank, status: 'failed')
    end

    it 'filters pending downloads' do
      results = Download.where(status: 'pending').all
      expect(results).to all(have_attributes(status: 'pending'))
      expect(results.size).to eq 1
    end

    it 'filters running downloads' do
      expect(Download.where(status: 'running').all.size).to eq 1
    end

    it 'filters success downloads' do
      results = Download.where(status: 'success').all
      expect(results).to all(have_attributes(status: 'success'))
    end

    it 'filters failed downloads' do
      results = Download.where(status: 'failed').all
      expect(results).to all(have_attributes(status: 'failed'))
    end

    it 'counts across all statuses' do
      expect(Download.count).to eq 4
    end
  end

  # ----------------------------------------------------------------
  # State transitions
  # ----------------------------------------------------------------
  describe 'state transitions' do
    let(:download) { create(:download, status: 'pending') }

    it '#mark_running! transitions to running and stamps started_at' do
      download.mark_running!
      d = download.reload
      expect(d.status).to eq 'running'
      expect(d.started_at).not_to be_nil
    end

    it '#mark_success! transitions to success, records file_path and completed_at' do
      download.mark_success!('/data/stmt_20260420.csv')
      d = download.reload
      expect(d.status).to eq 'success'
      expect(d.file_path).to eq '/data/stmt_20260420.csv'
      expect(d.completed_at).not_to be_nil
    end

    it '#mark_failed! transitions to failed, records error_message and completed_at' do
      download.mark_failed!('Connection refused')
      d = download.reload
      expect(d.status).to eq 'failed'
      expect(d.error_message).to eq 'Connection refused'
      expect(d.completed_at).not_to be_nil
    end

    it 'pending -> running -> success full lifecycle' do
      download.mark_running!
      expect(download.reload.status).to eq 'running'
      download.mark_success!('/path/file.csv')
      expect(download.reload.status).to eq 'success'
    end

    it 'pending -> running -> failed full lifecycle' do
      download.mark_running!
      download.mark_failed!('Timeout')
      d = download.reload
      expect(d.status).to eq 'failed'
      expect(d.error_message).to eq 'Timeout'
    end
  end

  # ----------------------------------------------------------------
  # #duration
  # ----------------------------------------------------------------
  describe '#duration' do
    it 'returns nil when not yet started' do
      d = Download.new(status: 'pending', account_id: 1, bank_id: 1, date: Date.today)
      expect(d.duration).to be_nil
    end

    it 'returns nil when started but not completed' do
      d = Download.new(status: 'running', account_id: 1, bank_id: 1, date: Date.today,
                       started_at: Time.now)
      expect(d.duration).to be_nil
    end

    it 'returns elapsed seconds when completed' do
      started   = Time.now - 7
      completed = Time.now
      d = Download.new(status: 'success', account_id: 1, bank_id: 1, date: Date.today,
                       started_at: started, completed_at: completed)
      expect(d.duration).to be_within(0.5).of(7)
    end
  end

  # ----------------------------------------------------------------
  # .for_date
  # ----------------------------------------------------------------
  describe '.for_date' do
    let(:account) { create(:account) }

    it 'returns only downloads matching the given date' do
      today_dl = create(:download, account: account, bank: account.bank, date: Date.today)
      _other   = create(:download, account: account, bank: account.bank, date: Date.today - 1)
      expect(Download.for_date(Date.today).all).to contain_exactly(today_dl)
    end

    it 'returns nothing when no downloads exist for the date' do
      expect(Download.for_date(Date.today - 365).all).to be_empty
    end
  end

  # ----------------------------------------------------------------
  # .recent
  # ----------------------------------------------------------------
  describe '.recent' do
    let(:account) { create(:account) }

    it 'returns at most N downloads' do
      12.times { create(:download, account: account, bank: account.bank) }
      expect(Download.recent(10).all.size).to eq 10
    end

    it 'returns all downloads when fewer than N exist' do
      3.times { create(:download, account: account, bank: account.bank) }
      expect(Download.recent(10).all.size).to eq 3
    end

    it 'returns the most recently created first' do
      older = create(:download, account: account, bank: account.bank,
                     created_at: Time.now - 3600)
      newer = create(:download, account: account, bank: account.bank,
                     created_at: Time.now)
      expect(Download.recent(2).all.first.id).to eq newer.id
    end
  end

  # ----------------------------------------------------------------
  # UI routes
  # ----------------------------------------------------------------
  describe 'UI routes' do
    let!(:account) { create(:account) }
    let!(:bank)    { account.bank }

    describe 'GET /jobs' do
      it 'returns 200' do
        get '/jobs'
        expect(last_response).to be_ok
      end

      it 'shows all downloads by default' do
        create(:download, account: account, bank: bank, status: 'success')
        create(:download, account: account, bank: bank, status: 'failed')
        get '/jobs'
        expect(last_response.body).to include('success', 'failed')
      end

      it 'filters by status=pending' do
        create(:download, account: account, bank: bank, status: 'pending')
        create(:download, account: account, bank: bank, status: 'success')
        get '/jobs', status: 'pending'
        expect(last_response.body).to     include('badge-pending')
        expect(last_response.body).not_to include('badge-success')
      end

      it 'filters by status=running' do
        create(:download, account: account, bank: bank, status: 'running')
        create(:download, account: account, bank: bank, status: 'failed')
        get '/jobs', status: 'running'
        expect(last_response.body).to     include('badge-running')
        expect(last_response.body).not_to include('badge-failed')
      end

      it 'filters by status=success' do
        create(:download, account: account, bank: bank, status: 'success')
        create(:download, account: account, bank: bank, status: 'failed')
        get '/jobs', status: 'success'
        expect(last_response.body).to     include('badge-success')
        expect(last_response.body).not_to include('badge-failed')
      end

      it 'filters by status=failed' do
        create(:download, account: account, bank: bank, status: 'failed', error_message: 'timeout')
        create(:download, account: account, bank: bank, status: 'success')
        get '/jobs', status: 'failed'
        expect(last_response.body).to     include('badge-failed')
        expect(last_response.body).not_to include('badge-success')
      end

      it 'filters by date' do
        today_dl = create(:download, account: account, bank: bank, date: Date.today)
        _old     = create(:download, account: account, bank: bank, date: Date.today - 10)
        get '/jobs', date: Date.today.to_s
        expect(last_response.body).to include(today_dl.id.to_s)
      end
    end

    describe 'GET /log' do
      it 'returns 200' do
        get '/log'
        expect(last_response).to be_ok
      end

      it 'shows download history' do
        create(:download, account: account, bank: bank, status: 'success')
        get '/log'
        expect(last_response.body).to include('success')
      end

      it 'filters by status=failed' do
        create(:download, account: account, bank: bank, status: 'failed', error_message: 'timeout')
        create(:download, account: account, bank: bank, status: 'success')
        get '/log', status: 'failed'
        expect(last_response.body).to     include('timeout')
        expect(last_response.body).not_to include('badge-success')
      end

      it 'filters by account_id' do
        other_account = create(:account, bank: bank)
        create(:download, account: account,       bank: bank, status: 'success')
        create(:download, account: other_account, bank: bank, status: 'failed')
        get '/log', account_id: other_account.id.to_s
        expect(last_response.body).to     include('failed')
        expect(last_response.body).not_to include('badge-success')
      end
    end
  end
end
