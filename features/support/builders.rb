# Shared helpers for building test records and email fixtures, mixed into the
# Cucumber World so step definitions can call them directly.

require 'mail'

module OctoBankXBuilders
  def find_or_create_bank(name, attrs = {})
    Bank.find(name: name) || Bank.create({
      name:             name,
      sftp_host:        'sftp.example.test',
      sftp_port:        22,
      sftp_remote_path: '/statements',
      sftp_username:    'user',
      sftp_password:    'pass',
      created_at:       Time.now,
      updated_at:       Time.now
    }.merge(attrs))
  end

  # A bare object that responds to #name — enough for SftpHelper.statement_filename.
  def bank_like(name)
    Struct.new(:name).new(name)
  end

  # Build a Mail message from `from` with a single attachment.
  def build_mail(from:, filename:, content: 'col1,col2')
    mail = Mail.new
    mail.from = from
    mail.to   = 'bot@bank.test'
    mail.subject = 'Statement'
    mail.attachments[filename] = content
    mail
  end

  # An IMAP ENVELOPE double whose from-address matches `email`.
  def imap_envelope(email)
    local, host = email.split('@')
    addr = double('Address', mailbox: local, host: host)
    double('Envelope', from: [addr])
  end

  def to_date(word)
    case word
    when 'today'    then Date.today
    when 'tomorrow' then Date.today + 1
    when 'yesterday' then Date.today - 1
    else Date.parse(word)
    end
  end

  # Build a Mail message with several attachments (comma-separated filenames).
  def build_mail_multi(from:, filenames:, content: 'col1,col2')
    mail = Mail.new
    mail.from = from
    filenames.each { |fn| mail.attachments[fn.strip] = content }
    mail
  end

  # Stub Net::IMAP with a fake inbox. `messages` is a list of
  # { id:, from:, filename: } hashes. Records interactions for assertions.
  def setup_imap_inbox(messages)
    @imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new) do |host, **opts|
      @imap_args = { host: host, opts: opts }
      @imap
    end
    allow(@imap).to receive(:login)  { |u, p| @imap_login = [u, p] }
    allow(@imap).to receive(:select) { |mbox| @imap_mailbox = mbox }
    allow(@imap).to receive(:search) { |crit| @imap_search = crit; messages.map { |m| m[:id] } }

    messages.each do |m|
      env = [double('FetchData', attr: { 'ENVELOPE' => imap_envelope(m[:from]) })]
      allow(@imap).to receive(:fetch).with(m[:id], 'ENVELOPE').and_return(env)
      mail = build_mail(from: m[:from], filename: m[:filename], content: "date,amount\n2026-05-25,1000\n")
      body = [double('FetchData', attr: { 'RFC822' => mail.to_s })]
      allow(@imap).to receive(:fetch).with(m[:id], 'RFC822').and_return(body)
    end

    @imap_stored = []
    allow(@imap).to receive(:store) { |id, flag, val| @imap_stored << [id, flag, val] }
    allow(@imap).to receive(:logout)
    allow(@imap).to receive(:disconnect)
    @imap
  end

  # Stub Net::POP3 with a fake inbox.
  def setup_pop_inbox(messages)
    @pop_deleted = 0
    pop_mails = messages.map do |m|
      mail = build_mail(from: m[:from], filename: m[:filename], content: "date,amount\n2026-05-25,500\n")
      pm   = double('POPMail', pop: mail.to_s)
      allow(pm).to receive(:delete) { @pop_deleted += 1; true }
      pm
    end

    session = double('POP3')
    allow(session).to receive(:each_mail) { |&blk| pop_mails.each(&blk) }
    allow(Net::POP3).to receive(:enable_ssl)
    allow(Net::POP3).to receive(:start) do |host, port, user, pass, &blk|
      @pop_args = { host: host, port: port, user: user, pass: pass }
      blk.call(session)
    end
    session
  end
end

World(OctoBankXBuilders)
