require_relative '../spec_helper'
require_relative '../../jobs/email_listener_job'

RSpec.describe EmailListenerJob do
  let(:bank)  { create(:bank, name: 'Leumi') }
  let(:bank2) { create(:bank, name: 'Poalim') }

  before do
    Setting.set('email_protocol', 'imap')
    Setting.set('email_host',     'imap.bank.test')
    Setting.set('email_port',     '993')
    Setting.set('EMAIL_USER',     'bot@bank.test')
    Setting.set('EMAIL_PWD',      'secret')
    Setting.set('email_ssl',      'true')
    Setting.set('download_dir',   Dir.mktmpdir('email_test'))
  end

  after { FileUtils.rm_rf(Setting['download_dir']) }

  # ----------------------------------------------------------------
  # Guard clauses — early returns
  # ----------------------------------------------------------------
  describe 'guard clauses' do
    it 'returns nil when email_host is not configured' do
      Setting.set('email_host', nil)
      expect(EmailListenerJob.run).to be_nil
    end

    it 'returns nil when the username is missing' do
      Setting.where(key: 'EMAIL_USER').delete
      expect(EmailListenerJob.run).to be_nil
    end

    it 'returns nil when the password is missing' do
      Setting.where(key: 'EMAIL_PWD').delete
      expect(EmailListenerJob.run).to be_nil
    end

    it 'does not touch the inbox when there are no active senders' do
      create(:email_sender, bank: bank, active: false)
      expect(Net::IMAP).not_to receive(:new)
      EmailListenerJob.run
    end
  end

  # ----------------------------------------------------------------
  # IMAP path
  # ----------------------------------------------------------------
  describe 'IMAP fetch' do
    let!(:sender) do
      create(:email_sender,
        sender_email: 'statements@leumi.co.il',
        sender_name:  'Leumi Statements',
        bank:         bank,
        active:       true
      )
    end

    let(:mock_imap)   { instance_double(Net::IMAP) }
    let(:csv_content) { "date,amount\n2026-05-25,1000\n" }

    let(:envelope) do
      from_addr = double('Address', mailbox: 'statements', host: 'leumi.co.il')
      double('Envelope', from: [from_addr])
    end

    let(:fetch_envelope_result) do
      [double('FetchData', attr: { 'ENVELOPE' => envelope })]
    end

    let(:mail_with_attachment) do
      mail = Mail.new do
        from    'statements@leumi.co.il'
        to      'bot@bank.test'
        subject 'Daily statement'
      end
      mail.attachments['statement_20260525.csv'] = csv_content
      mail
    end

    let(:fetch_body_result) do
      [double('FetchData', attr: { 'RFC822' => mail_with_attachment.to_s })]
    end

    before do
      allow(Net::IMAP).to receive(:new).and_return(mock_imap)
      allow(mock_imap).to receive(:login)
      allow(mock_imap).to receive(:select)
      allow(mock_imap).to receive(:search).and_return([1])
      allow(mock_imap).to receive(:fetch).with(1, 'ENVELOPE').and_return(fetch_envelope_result)
      allow(mock_imap).to receive(:fetch).with(1, 'RFC822').and_return(fetch_body_result)
      allow(mock_imap).to receive(:store)
      allow(mock_imap).to receive(:expunge)
      allow(mock_imap).to receive(:logout)
      allow(mock_imap).to receive(:disconnect)
    end

    it 'connects to the IMAP server with the configured credentials' do
      expect(Net::IMAP).to receive(:new).with('imap.bank.test', port: 993, ssl: true)
      expect(mock_imap).to receive(:login).with('bot@bank.test', 'secret')
      EmailListenerJob.run
    end

    it 'uses EMAIL_USER and EMAIL_PWD when both legacy and new keys exist' do
      Setting.set('email_username', 'legacy@bank.test')
      Setting.set('email_password', 'legacy-pwd')
      expect(mock_imap).to receive(:login).with('bot@bank.test', 'secret')
      EmailListenerJob.run
    end

    it 'falls back to legacy email_username / email_password' do
      Setting.where(key: 'EMAIL_USER').delete
      Setting.where(key: 'EMAIL_PWD').delete
      Setting.set('email_username', 'legacy@bank.test')
      Setting.set('email_password', 'legacy-pwd')
      expect(mock_imap).to receive(:login).with('legacy@bank.test', 'legacy-pwd')
      EmailListenerJob.run
    end

    it 'selects the INBOX' do
      expect(mock_imap).to receive(:select).with('INBOX')
      EmailListenerJob.run
    end

    it 'scans all messages' do
      expect(mock_imap).to receive(:search).with(['ALL']).and_return([])
      EmailListenerJob.run
    end

    it 'downloads CSV attachments from approved senders' do
      EmailListenerJob.run

      download_dir = Setting['download_dir']
      files = Dir.glob(File.join(download_dir, '**', '*.csv'))
      expect(files.size).to eq 1
      expect(File.basename(files.first)).to eq 'statement_20260525.csv'
    end

    it 'creates a Download record on success' do
      expect { EmailListenerJob.run }.to change(Download, :count).by(1)

      dl = Download.last
      expect(dl.bank_id).to eq bank.id
      expect(dl.status).to eq 'success'
      expect(dl.file_path).to include('statement_20260525.csv')
    end

    it 'marks the message as Seen after processing' do
      expect(mock_imap).to receive(:store).with(1, '+FLAGS', [:Seen])
      EmailListenerJob.run
    end

    it 'deletes messages from unapproved senders' do
      unknown = double('Envelope', from: [double('Address', mailbox: 'hacker', host: 'evil.com')])
      allow(mock_imap).to receive(:fetch).with(1, 'ENVELOPE')
        .and_return([double('FetchData', attr: { 'ENVELOPE' => unknown })])

      expect(mock_imap).to receive(:store).with(1, '+FLAGS', [:Deleted])
      expect(mock_imap).to receive(:expunge)
      expect { EmailListenerJob.run }.not_to change(Download, :count)
    end

    it 'does not download the same file twice' do
      EmailListenerJob.run
      expect { EmailListenerJob.run }.not_to change(Download, :count)
    end

    it 'accepts xlsx attachments' do
      mail_xlsx = Mail.new do
        from    'statements@leumi.co.il'
        to      'bot@bank.test'
        subject 'Excel report'
      end
      mail_xlsx.attachments['report.xlsx'] = 'PK...'

      allow(mock_imap).to receive(:fetch).with(1, 'RFC822')
        .and_return([double('FetchData', attr: { 'RFC822' => mail_xlsx.to_s })])

      expect { EmailListenerJob.run }.to change(Download, :count).by(1)
    end

    it 'ignores non-document attachments' do
      mail_img = Mail.new do
        from    'statements@leumi.co.il'
        to      'bot@bank.test'
        subject 'Photo'
      end
      mail_img.attachments['photo.jpg'] = "\xFF\xD8\xFF"

      allow(mock_imap).to receive(:fetch).with(1, 'RFC822')
        .and_return([double('FetchData', attr: { 'RFC822' => mail_img.to_s })])

      expect { EmailListenerJob.run }.not_to change(Download, :count)
    end

    it 'processes multiple messages with distinct files' do
      allow(mock_imap).to receive(:search).and_return([1, 2])
      allow(mock_imap).to receive(:fetch).with(2, 'ENVELOPE').and_return(fetch_envelope_result)

      second_mail = Mail.new do
        from    'statements@leumi.co.il'
        to      'bot@bank.test'
        subject 'Second statement'
      end
      second_mail.attachments['statement_20260526.csv'] = csv_content
      allow(mock_imap).to receive(:fetch).with(2, 'RFC822')
        .and_return([double('FetchData', attr: { 'RFC822' => second_mail.to_s })])

      expect { EmailListenerJob.run }.to change(Download, :count).by(2)
    end

    it 'ensures logout and disconnect even on error' do
      allow(mock_imap).to receive(:search).and_raise(Net::IMAP::Error.new('timeout'))
      expect(mock_imap).to receive(:logout)
      expect(mock_imap).to receive(:disconnect)

      expect { EmailListenerJob.run }.to raise_error(Net::IMAP::Error)
    end
  end

  # ----------------------------------------------------------------
  # POP3 path
  # ----------------------------------------------------------------
  describe 'POP3 fetch' do
    let!(:sender) do
      create(:email_sender,
        sender_email: 'reports@poalim.co.il',
        sender_name:  'Poalim Reports',
        bank:         bank2,
        active:       true
      )
    end

    let(:csv_content) { "date,amount\n2026-05-25,500\n" }

    let(:pop_mail) do
      mail = Mail.new do
        from    'reports@poalim.co.il'
        to      'bot@bank.test'
        subject 'Daily report'
      end
      mail.attachments['report.csv'] = csv_content
      mail
    end

    let(:mock_pop_mail) { double('POPMail', pop: pop_mail.to_s, delete: true) }

    before do
      Setting.set('email_protocol', 'pop')
      Setting.set('email_port', '995')
      allow(Net::POP3).to receive(:enable_ssl)
    end

    it 'uses POP3 when protocol is set to pop' do
      pop_session = double('POP3')
      allow(pop_session).to receive(:each_mail).and_yield(mock_pop_mail)
      allow(Net::POP3).to receive(:start).and_yield(pop_session)

      expect(Net::POP3).to receive(:start).with('imap.bank.test', 995, 'bot@bank.test', 'secret')
      EmailListenerJob.run
    end

    it 'downloads attachments from approved POP3 senders' do
      pop_session = double('POP3')
      allow(pop_session).to receive(:each_mail).and_yield(mock_pop_mail)
      allow(Net::POP3).to receive(:start).and_yield(pop_session)

      expect { EmailListenerJob.run }.to change(Download, :count).by(1)

      dl = Download.last
      expect(dl.bank_id).to eq bank2.id
      expect(dl.status).to eq 'success'
    end

    it 'deletes the message after processing' do
      pop_session = double('POP3')
      allow(pop_session).to receive(:each_mail).and_yield(mock_pop_mail)
      allow(Net::POP3).to receive(:start).and_yield(pop_session)

      expect(mock_pop_mail).to receive(:delete)
      EmailListenerJob.run
    end

    it 'deletes messages from unapproved senders without downloading' do
      bad_mail = Mail.new do
        from    'unknown@evil.com'
        to      'bot@bank.test'
        subject 'Phishing'
      end
      bad_mail.attachments['malware.csv'] = 'bad'

      bad_pop     = double('POPMail', pop: bad_mail.to_s)
      pop_session = double('POP3')
      allow(pop_session).to receive(:each_mail).and_yield(bad_pop)
      allow(Net::POP3).to receive(:start).and_yield(pop_session)

      expect(bad_pop).to receive(:delete)
      expect { EmailListenerJob.run }.not_to change(Download, :count)
    end
  end

  # ----------------------------------------------------------------
  # .process_attachments
  # ----------------------------------------------------------------
  describe '.process_attachments' do
    let(:download_dir) { Dir.mktmpdir('attach_test') }

    after { FileUtils.rm_rf(download_dir) }

    it 'creates the bank subfolder from bank name' do
      mail = Mail.new
      mail.attachments['data.csv'] = 'col1,col2'

      EmailListenerJob.send(:process_attachments, mail, bank.id, download_dir)

      expect(Dir.exist?(File.join(download_dir, 'leumi'))).to be true
    end

    it 'saves the attachment content correctly' do
      content = "date,amount\n2026-01-01,999"
      mail = Mail.new
      mail.attachments['test.csv'] = content

      EmailListenerJob.send(:process_attachments, mail, bank.id, download_dir)

      saved = File.read(File.join(download_dir, 'leumi', 'test.csv'))
      expect(saved).to eq content
    end

    it 'skips non-matching file extensions' do
      mail = Mail.new
      mail.attachments['image.png'] = "\x89PNG"

      expect {
        EmailListenerJob.send(:process_attachments, mail, bank.id, download_dir)
      }.not_to change(Download, :count)
    end

    it 'handles multiple attachments in one email' do
      mail = Mail.new
      mail.attachments['file1.csv'] = 'a,b'
      mail.attachments['file2.txt'] = 'c,d'
      mail.attachments['file3.jpg'] = 'img' # should be skipped

      expect {
        EmailListenerJob.send(:process_attachments, mail, bank.id, download_dir)
      }.to change(Download, :count).by(2)
    end

    it 'does not save the same file twice' do
      mail = Mail.new
      mail.attachments['dupe.csv'] = 'a,b'

      EmailListenerJob.send(:process_attachments, mail, bank.id, download_dir)
      expect {
        EmailListenerJob.send(:process_attachments, mail, bank.id, download_dir)
      }.not_to change(Download, :count)
    end
  end

  # ----------------------------------------------------------------
  # Protocol / settings defaults
  # ----------------------------------------------------------------
  describe 'protocol defaults' do
    it 'defaults to IMAP when protocol is not set' do
      Setting.where(key: 'email_protocol').delete
      create(:email_sender, bank: bank, active: true)

      mock_imap = instance_double(Net::IMAP)
      allow(Net::IMAP).to receive(:new).and_return(mock_imap)
      allow(mock_imap).to receive(:login)
      allow(mock_imap).to receive(:select)
      allow(mock_imap).to receive(:search).and_return([])
      allow(mock_imap).to receive(:expunge)
      allow(mock_imap).to receive(:logout)
      allow(mock_imap).to receive(:disconnect)

      expect(Net::IMAP).to receive(:new)
      EmailListenerJob.run
    end

    it 'defaults to port 995 for POP when port is not set' do
      Setting.set('email_protocol', 'pop')
      Setting.where(key: 'email_port').delete
      create(:email_sender, bank: bank, active: true)

      pop_session = double('POP3')
      allow(pop_session).to receive(:each_mail)
      allow(Net::POP3).to receive(:enable_ssl)
      allow(Net::POP3).to receive(:start).and_yield(pop_session)

      expect(Net::POP3).to receive(:start).with('imap.bank.test', 995, 'bot@bank.test', 'secret')
      EmailListenerJob.run
    end
  end
end
