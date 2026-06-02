require_relative '../spec_helper'
require_relative '../../helpers/sftp_helper'

RSpec.describe SftpHelper do
  let(:bank) do
    create(:bank,
      name:             'בנק לאומי',
      sftp_host:        'sftp.leumi.co.il',
      sftp_port:        22,
      sftp_remote_path: '/statements',
      sftp_username:    'octobankx',
      sftp_password:    'secret123'
    )
  end

  let(:date)         { Date.new(2026, 5, 25) }
  let(:download_dir) { Dir.mktmpdir('octobankx_test') }

  after { FileUtils.rm_rf(download_dir) }

  # ----------------------------------------------------------------
  # .statement_filename
  # ----------------------------------------------------------------
  describe '.statement_filename' do
    it 'returns YYYYMMDD_<bank_slug>.csv' do
      result = described_class.statement_filename(bank, date)
      expect(result).to eq '20260525_בנק_לאומי.csv'
    end

    it 'downcases the bank slug' do
      bank_en = build(:bank, name: 'Bank Leumi')
      result  = described_class.statement_filename(bank_en, date)
      expect(result).to eq '20260525_bank_leumi.csv'
    end

    it 'replaces spaces with underscores' do
      bank_spaces = build(:bank, name: 'My  Big  Bank')
      result      = described_class.statement_filename(bank_spaces, date)
      expect(result).to eq '20260525_my_big_bank.csv'
    end
  end

  # ----------------------------------------------------------------
  # .download  — success path (mocked SFTP)
  # ----------------------------------------------------------------
  describe '.download' do
    let(:mock_sftp) { instance_double('Net::SFTP::Session') }

    context 'when the SFTP connection succeeds' do
      before do
        # Stub Net::SFTP.start to yield our mock session
        allow(Net::SFTP).to receive(:start).and_yield(mock_sftp)
        allow(mock_sftp).to receive(:download!)
        allow(mock_sftp).to receive(:remove!)
      end

      it 'returns the local file path' do
        result = described_class.download(
          bank: bank, date: date, download_dir: download_dir, timeout: 10
        )
        expect(result).to include(download_dir)
        expect(result).to end_with('.csv')
      end

      it 'connects with the bank SFTP credentials' do
        expect(Net::SFTP).to receive(:start).with(
          'sftp.leumi.co.il',
          'octobankx',
          hash_including(
            password:        'secret123',
            port:            22,
            timeout:         10,
            non_interactive: true
          )
        ).and_yield(mock_sftp)

        described_class.download(
          bank: bank, date: date, download_dir: download_dir, timeout: 10
        )
      end

      it 'downloads from the correct remote path' do
        expected_remote = '/statements/20260525_בנק_לאומי.csv'
        expect(mock_sftp).to receive(:download!).with(expected_remote, anything)

        described_class.download(
          bank: bank, date: date, download_dir: download_dir, timeout: 10
        )
      end

      it 'creates the local bank directory' do
        described_class.download(
          bank: bank, date: date, download_dir: download_dir, timeout: 10
        )
        bank_dir = File.join(download_dir, 'בנק_לאומי')
        expect(Dir.exist?(bank_dir)).to be true
      end
    end

    # ----------------------------------------------------------------
    # .download  — error handling
    # ----------------------------------------------------------------
    context 'when SFTP authentication fails' do
      before do
        allow(Net::SFTP).to receive(:start)
          .and_raise(Net::SSH::AuthenticationFailed.new('octobankx'))
      end

      it 'raises with a descriptive auth error message' do
        expect {
          described_class.download(bank: bank, date: date, download_dir: download_dir)
        }.to raise_error(/SFTP authentication failed/)
      end
    end

    context 'when the remote file does not exist' do
      before do
        allow(Net::SFTP).to receive(:start)
          .and_raise(Net::SFTP::StatusException.new(
            double(code: 2, message: nil), 'no such file'
          ))
      end

      it 'raises with an SFTP status error' do
        expect {
          described_class.download(bank: bank, date: date, download_dir: download_dir)
        }.to raise_error(/SFTP status error/)
      end
    end

    context 'when the connection is refused' do
      before do
        allow(Net::SFTP).to receive(:start)
          .and_raise(Errno::ECONNREFUSED.new('connection refused'))
      end

      it 'raises with a connection error' do
        expect {
          described_class.download(bank: bank, date: date, download_dir: download_dir)
        }.to raise_error(/SFTP connection failed/)
      end
    end

    context 'when a SocketError occurs' do
      before do
        allow(Net::SFTP).to receive(:start)
          .and_raise(SocketError.new('getaddrinfo: Name or service not known'))
      end

      it 'raises with a connection error' do
        expect {
          described_class.download(bank: bank, date: date, download_dir: download_dir)
        }.to raise_error(/SFTP connection failed/)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(Net::SFTP).to receive(:start)
          .and_raise(RuntimeError.new('something went wrong'))
      end

      it 'raises with a generic SFTP error' do
        expect {
          described_class.download(bank: bank, date: date, download_dir: download_dir)
        }.to raise_error(/SFTP error/)
      end
    end

    context 'with a non-standard port' do
      let(:bank_custom_port) do
        create(:bank, name: 'Custom Port Bank', sftp_host: 'sftp.custom.co.il',
               sftp_port: 2222, sftp_remote_path: '/daily',
               sftp_username: 'user', sftp_password: 'pass')
      end

      it 'passes the custom port to Net::SFTP.start' do
        mock = instance_double('Net::SFTP::Session')
        allow(mock).to receive(:download!)
        allow(mock).to receive(:remove!)

        expect(Net::SFTP).to receive(:start).with(
          'sftp.custom.co.il', 'user',
          hash_including(port: 2222)
        ).and_yield(mock)

        described_class.download(
          bank: bank_custom_port, date: date, download_dir: download_dir
        )
      end
    end
  end
end
