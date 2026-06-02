# Steps for the full SFTP download process: login, download, remote delete,
# and ZIP extraction into the bank's target folder.
# The SFTP connection is stubbed, but the downloaded file and extraction are real.

require_relative '../../helpers/sftp_helper'

Given('a temporary target folder') do
  @target_folder = Dir.mktmpdir('octobankx_target')
end

Given('a bank {string} configured for SFTP using that target folder') do |name|
  @bank = find_or_create_bank(name,
    sftp_host:        'sftp.test',
    sftp_port:        22,
    sftp_remote_path: '/statements',
    sftp_username:    'octobankx',
    sftp_password:    'secret',
    target_folder:    @target_folder)
end

Given('the remote statement is a ZIP archive containing:') do |table|
  entries = table.hashes.each_with_object({}) { |row, h| h[row['filename']] = row['content'] }
  @provision = ->(local) { write_zip(local, entries) }
  setup_sftp_provision
end

Given('the remote statement is a plain CSV file') do
  @provision = ->(local) { File.write(local, "date,amount\n2026-05-25,100\n") }
  setup_sftp_provision
end

When('the bank\'s statement is downloaded over SFTP for {string}') do |date|
  @download_dir = Dir.mktmpdir('octobankx_dl')
  @result = SftpHelper.download(bank: @bank, date: Date.parse(date),
                                download_dir: @download_dir, timeout: 10)
end

Then('the SFTP session logs in as {string}') do |user|
  expect(@sftp_args[:user]).to eq user
end

Then('the statement file is downloaded from {string}') do |remote|
  expect(@downloaded_remote).to eq remote
end

Then('the remote statement file is deleted from the server') do
  expect(@removed).to include(@downloaded_remote)
end

Then('the target folder contains {string}') do |name|
  expect(File.exist?(File.join(@target_folder, name))).to be true
end

Then('the target folder is empty') do
  expect(Dir.children(@target_folder)).to be_empty
end
