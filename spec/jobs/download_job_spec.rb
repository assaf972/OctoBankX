require_relative '../spec_helper'
require_relative '../../jobs/download_job'

RSpec.describe DownloadJob do
  let!(:bank_a) do
    create(:bank, name: 'Bank A', sftp_host: 'sftp.a.com',
           sftp_username: 'user_a', sftp_password: 'pass_a')
  end
  let!(:bank_b) do
    create(:bank, name: 'Bank B', sftp_host: 'sftp.b.com',
           sftp_username: 'user_b', sftp_password: 'pass_b')
  end
  let(:today) { Date.today }

  # ----------------------------------------------------------------
  # .enqueue
  # ----------------------------------------------------------------
  describe '.enqueue' do
    it 'creates a pending download for every bank' do
      expect { described_class.enqueue(date: today) }
        .to change(Download, :count).by(2)

      statuses = Download.where(date: today).map(:status)
      expect(statuses).to all(eq 'pending')
    end

    it 'does not duplicate downloads for a bank on the same date' do
      described_class.enqueue(date: today)
      expect { described_class.enqueue(date: today) }
        .not_to change(Download, :count)
    end

    it 'can enqueue for different dates independently' do
      described_class.enqueue(date: today)
      tomorrow = today + 1
      expect { described_class.enqueue(date: tomorrow) }
        .to change(Download, :count).by(2)
    end

    it 'sets bank_id and date on each download' do
      described_class.enqueue(date: today)
      dl = Download.where(bank_id: bank_a.id, date: today).first
      expect(dl).not_to be_nil
      expect(dl.status).to eq 'pending'
    end
  end

  # ----------------------------------------------------------------
  # .process  — success
  # ----------------------------------------------------------------
  describe '.process' do
    let(:download) do
      Download.create(bank_id: bank_a.id, date: today,
                      status: 'pending', created_at: Time.now)
    end

    context 'when SFTP succeeds' do
      before do
        allow(SftpHelper).to receive(:download)
          .and_return('/downloads/bank_a/20260525_bank_a.csv')
      end

      it 'marks the download as running then success' do
        described_class.process(download, download_dir: '/downloads', timeout: 10)

        download.reload
        expect(download.status).to eq 'success'
        expect(download.file_path).to eq '/downloads/bank_a/20260525_bank_a.csv'
        expect(download.started_at).not_to be_nil
        expect(download.completed_at).not_to be_nil
      end

      it 'passes the correct arguments to SftpHelper' do
        expect(SftpHelper).to receive(:download).with(
          bank:         bank_a,
          date:         today,
          download_dir: '/downloads',
          timeout:      10
        )
        described_class.process(download, download_dir: '/downloads', timeout: 10)
      end
    end

    context 'when SFTP fails' do
      before do
        allow(SftpHelper).to receive(:download)
          .and_raise(StandardError.new('Connection timed out'))
      end

      it 'marks the download as failed with error message' do
        described_class.process(download, download_dir: '/downloads', timeout: 10)

        download.reload
        expect(download.status).to eq 'failed'
        expect(download.error_message).to eq 'Connection timed out'
        expect(download.completed_at).not_to be_nil
      end

      it 'does not raise — the error is captured' do
        expect {
          described_class.process(download, download_dir: '/downloads', timeout: 10)
        }.not_to raise_error
      end
    end
  end

  # ----------------------------------------------------------------
  # .run  — full orchestration
  # ----------------------------------------------------------------
  describe '.run' do
    before do
      allow(SftpHelper).to receive(:download) do |bank:, date:, **|
        "/downloads/#{bank.name.downcase.tr(' ', '_')}/file.csv"
      end
    end

    it 'enqueues and processes all banks' do
      described_class.run(date: today)

      downloads = Download.where(date: today).all
      expect(downloads.size).to eq 2
      expect(downloads.map(&:status)).to all(eq 'success')
    end

    it 'uses the download_dir from settings when available' do
      Setting.set('download_dir', '/custom/path')

      expect(SftpHelper).to receive(:download)
        .with(hash_including(download_dir: '/custom/path'))
        .twice
        .and_return('/custom/path/file.csv')

      described_class.run(date: today)
    end

    it 'uses the sftp_timeout from settings' do
      Setting.set('sftp_timeout', '60')

      expect(SftpHelper).to receive(:download)
        .with(hash_including(timeout: 60))
        .twice
        .and_return('/tmp/file.csv')

      described_class.run(date: today)
    end

    it 'skips banks that already have a download for the date' do
      Download.create(bank_id: bank_a.id, date: today,
                      status: 'success', created_at: Time.now)

      described_class.run(date: today)

      # bank_a should NOT get a new download, bank_b should
      bank_a_downloads = Download.where(bank_id: bank_a.id, date: today).count
      bank_b_downloads = Download.where(bank_id: bank_b.id, date: today).count
      expect(bank_a_downloads).to eq 1
      expect(bank_b_downloads).to eq 1
    end

    it 'continues processing other banks if one fails' do
      call_count = 0
      allow(SftpHelper).to receive(:download) do |bank:, **|
        call_count += 1
        raise 'SFTP error' if bank.id == bank_a.id
        "/downloads/#{bank.name}/file.csv"
      end

      described_class.run(date: today)

      dl_a = Download.where(bank_id: bank_a.id, date: today).first
      dl_b = Download.where(bank_id: bank_b.id, date: today).first
      expect(dl_a.status).to eq 'failed'
      expect(dl_b.status).to eq 'success'
      expect(call_count).to eq 2
    end

    it 'defaults to today when no date is given' do
      described_class.run
      expect(Download.where(date: Date.today).count).to eq 2
    end
  end
end
