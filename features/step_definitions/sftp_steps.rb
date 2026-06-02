# Steps for SftpHelper, ported from spec/helpers/sftp_helper_spec.rb.
# Net::SFTP is stubbed so no real server is needed.

require_relative '../../helpers/sftp_helper'

# --- statement_filename --------------------------------------------

When('I build the statement filename for a bank named {string} on {string}') do |name, date|
  @result = SftpHelper.statement_filename(bank_like(name), Date.parse(date))
end

Then('the statement filename should be {string}') do |expected|
  expect(@result).to eq expected
end

# --- bank under test ------------------------------------------------

Given('a bank {string} with host {string} port {int} path {string} user {string} password {string}') do |name, host, port, path, user, pass|
  @bank = find_or_create_bank(name,
    sftp_host: host, sftp_port: port, sftp_remote_path: path,
    sftp_username: user, sftp_password: pass)
end

# --- download: success path ----------------------------------------

Given('the SFTP server accepts the connection') do
  @download_calls = []
  sftp = double('Net::SFTP::Session')
  allow(sftp).to receive(:download!) { |remote, local| @download_calls << [remote, local] }
  allow(Net::SFTP).to receive(:start) do |host, user, opts, &blk|
    @sftp_args = { host: host, user: user, opts: opts }
    blk.call(sftp)
  end
end

# --- download: error paths -----------------------------------------

Given('the SFTP connection raises {string}') do |kind|
  err =
    case kind
    when 'authentication failure' then Net::SSH::AuthenticationFailed.new('user')
    when 'a missing remote file'  then Net::SFTP::StatusException.new(double(code: 2, message: nil), 'no such file')
    when 'a refused connection'   then Errno::ECONNREFUSED.new('connection refused')
    when 'a socket error'         then SocketError.new('getaddrinfo failed')
    when 'an unexpected error'    then RuntimeError.new('something went wrong')
    else raise "Unknown SFTP error kind: #{kind}"
    end
  allow(Net::SFTP).to receive(:start).and_raise(err)
end

When('I download statements for the bank on {string}') do |date|
  @download_dir = Dir.mktmpdir('octobankx_cuke')
  begin
    @result = SftpHelper.download(bank: @bank, date: Date.parse(date),
                                  download_dir: @download_dir, timeout: 10)
  rescue StandardError => e
    @error = e
  end
end

# --- download assertions -------------------------------------------

Then('the download returns a csv path inside the download directory') do
  expect(@result).to include(@download_dir)
  expect(@result).to end_with('.csv')
end

Then('it connected to host {string} as user {string} on port {int}') do |host, user, port|
  expect(@sftp_args[:host]).to eq host
  expect(@sftp_args[:user]).to eq user
  expect(@sftp_args[:opts]).to include(port: port, non_interactive: true)
end

Then('it requested the remote file {string}') do |remote|
  expect(@download_calls.first.first).to eq remote
end

Then('the local directory {string} should exist under the download directory') do |slug|
  expect(Dir.exist?(File.join(@download_dir, slug))).to be true
end

Then('the download fails with a message matching {string}') do |pattern|
  expect(@error).not_to be_nil
  expect(@error.message).to match(Regexp.new(pattern))
end
