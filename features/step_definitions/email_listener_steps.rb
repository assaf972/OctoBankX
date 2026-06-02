# Steps for EmailListenerJob, ported from spec/jobs/email_listener_job_spec.rb.
# Net::IMAP / Net::POP3 / Mail are stubbed so no real mail server is needed.

require 'net/imap'
require 'net/pop'
require_relative '../../jobs/email_listener_job'

# --- Configuration --------------------------------------------------

def configure_email_listener(protocol, port)
  @download_dir = Dir.mktmpdir('email_cuke')
  Setting.set('email_protocol', protocol)
  Setting.set('email_host',     'imap.bank.test')
  Setting.set('email_port',     port)
  Setting.set('EMAIL_USER',     'bot@bank.test')
  Setting.set('EMAIL_PWD',      'secret')
  Setting.set('email_ssl',      'true')
  Setting.set('download_dir',   @download_dir)
end

Given('the email listener is configured for IMAP') { configure_email_listener('imap', '993') }
Given('the email listener is configured for POP3') { configure_email_listener('pop', '995') }

Given('the setting {string} is removed') do |key|
  Setting.where(key: key).delete
end

Given('the email server is stubbed but should not be used') do
  spy = instance_double(Net::IMAP)
  allow(spy).to receive(:login)
  allow(spy).to receive(:select)
  allow(spy).to receive(:search).and_return([])
  allow(spy).to receive(:logout)
  allow(spy).to receive(:disconnect)
  allow(Net::IMAP).to receive(:new).and_return(spy)
end

# --- Senders --------------------------------------------------------

Given('an approved sender {string} for bank {string}') do |email, bank_name|
  bank = find_or_create_bank(bank_name)
  EmailSender.create(sender_name: 'Approved', sender_email: email, bank_id: bank.id,
                     active: true, created_at: Time.now, updated_at: Time.now)
end

Given('an inactive sender {string} for bank {string}') do |email, bank_name|
  bank = find_or_create_bank(bank_name)
  EmailSender.create(sender_name: 'Inactive', sender_email: email, bank_id: bank.id,
                     active: false, created_at: Time.now, updated_at: Time.now)
end

# --- Inboxes --------------------------------------------------------

Given('an IMAP inbox with a message from {string} attaching {string}') do |from, filename|
  setup_imap_inbox([{ id: 1, from: from, filename: filename }])
end

Given('an IMAP inbox with two messages from {string} attaching distinct files') do |from|
  setup_imap_inbox([{ id: 1, from: from, filename: 'statement_1.csv' },
                    { id: 2, from: from, filename: 'statement_2.csv' }])
end

Given('the IMAP search will raise an error') do
  allow(@imap).to receive(:search).and_raise(Net::IMAP::Error.new('timeout'))
end

Given('a POP3 inbox with a message from {string} attaching {string}') do |from, filename|
  setup_pop_inbox([{ id: 1, from: from, filename: filename }])
end

# --- Action ---------------------------------------------------------

When('the email listener runs') do
  begin
    @result = EmailListenerJob.run
  rescue StandardError => e
    @error = e
  end
end

When('the email listener runs again') do
  EmailListenerJob.run
end

When('I process an email from {string} with attachments {string} for bank {string}') do |from, files, bank_name|
  @download_dir ||= Dir.mktmpdir('email_cuke')
  bank = find_or_create_bank(bank_name)
  mail = build_mail_multi(from: from, filenames: files.split(','))
  EmailListenerJob.send(:process_attachments, mail, bank.id, @download_dir)
end

# --- Assertions: connection -----------------------------------------

Then('it connects to the IMAP server {string} on port {int}') do |host, port|
  expect(@imap_args[:host]).to eq host
  expect(@imap_args[:opts]).to include(port: port, ssl: true)
end

Then('it logs in as {string}') do |user|
  expect(@imap_login.first).to eq user
end

Then('it selects the {string} mailbox') do |mbox|
  expect(@imap_mailbox).to eq mbox
end

Then('it scans all messages') do
  expect(@imap_search).to eq ['ALL']
end

Then('message {int} is marked as seen') do |id|
  expect(@imap_stored).to include([id, '+FLAGS', [:Seen]])
end

Then('message {int} is deleted from the server') do |id|
  expect(@imap_stored).to include([id, '+FLAGS', [:Deleted]])
end

Then('it logs out and disconnects') do
  expect(@imap).to have_received(:logout)
  expect(@imap).to have_received(:disconnect)
end

Then('the listener raises an IMAP error') do
  expect(@error).to be_a(Net::IMAP::Error)
end

Then('it connects to the POP3 server {string} on port {int} as {string}') do |host, port, user|
  expect(@pop_args).to include(host: host, port: port, user: user)
end

Then('the message is deleted after processing') do
  expect(@pop_deleted).to be >= 1
end

Then('the email server should not be contacted') do
  expect(Net::IMAP).not_to have_received(:new)
end

# --- Assertions: results --------------------------------------------

Then('a successful download is recorded for bank {string}') do |bank_name|
  bank = Bank.find(name: bank_name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl).not_to be_nil
  expect(dl.status).to eq 'success'
end

Then('no download is recorded') do
  expect(Download.count).to eq 0
end

Then('{int} download(s) should be recorded') do |count|
  expect(Download.count).to eq count
end

Then('{int} file(s) should be saved in the download directory') do |count|
  files = Dir.glob(File.join(@download_dir, '**', '*'))
  files.select! { |f| File.file?(f) }
  expect(files.size).to eq count
end

Then('a file named {string} should be saved') do |name|
  files = Dir.glob(File.join(@download_dir, '**', name))
  expect(files).not_to be_empty
end

Then('the listener returns nothing') do
  expect(@result).to be_nil
end

Then('the bank subfolder {string} should exist') do |slug|
  expect(Dir.exist?(File.join(@download_dir, slug))).to be true
end
