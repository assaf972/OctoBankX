# Steps for DownloadJob, ported from spec/jobs/download_job_spec.rb.
# SftpHelper.download is stubbed; calls are captured in @sftp_calls.

require_relative '../../jobs/download_job'

# --- SftpHelper stubs ----------------------------------------------

Given('the SFTP helper succeeds for every bank') do
  @sftp_calls = []
  allow(SftpHelper).to receive(:download) do |bank:, date:, download_dir:, timeout:|
    @sftp_calls << { bank: bank, date: date, download_dir: download_dir, timeout: timeout }
    "/downloads/#{bank.name.downcase.tr(' ', '_')}/file.csv"
  end
end

Given('the SFTP helper fails for bank {string} and succeeds otherwise') do |failing|
  @sftp_calls = []
  allow(SftpHelper).to receive(:download) do |bank:, **|
    @sftp_calls << bank.name
    raise 'SFTP error' if bank.name == failing
    "/downloads/#{bank.name}/file.csv"
  end
end

Given('the SFTP helper returns {string}') do |path|
  @sftp_calls = []
  allow(SftpHelper).to receive(:download) do |**kw|
    @sftp_calls << kw
    path
  end
end

Given('the SFTP helper raises {string}') do |message|
  allow(SftpHelper).to receive(:download).and_raise(StandardError.new(message))
end

# --- Actions --------------------------------------------------------

When('I enqueue downloads for {string}') do |date|
  DownloadJob.enqueue(date: to_date(date))
end

When('I run the download job for {string}') do |date|
  DownloadJob.run(date: to_date(date))
end

When('I run the download job with no date') do
  DownloadJob.run
end

When('I process the pending download for bank {string}') do |name|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id, status: 'pending').first
  DownloadJob.process(dl, download_dir: '/downloads', timeout: 10)
end

# --- Assertions -----------------------------------------------------

Then('there should be {int} download(s) for {string}') do |count, date|
  expect(Download.where(date: to_date(date)).count).to eq count
end

Then('every download for {string} should have status {string}') do |date, status|
  statuses = Download.where(date: to_date(date)).map(:status)
  expect(statuses).not_to be_empty
  expect(statuses.uniq).to eq [status]
end

Then('the download for bank {string} should have status {string}') do |name, status|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl.status).to eq status
end

Then('the download for bank {string} should have file path {string}') do |name, path|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl.file_path).to eq path
end

Then('the download for bank {string} should have started and completed timestamps') do |name|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl.started_at).not_to be_nil
  expect(dl.completed_at).not_to be_nil
end

Then('the download for bank {string} should have error message {string}') do |name, msg|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl.error_message).to eq msg
end

Then('the download for bank {string} should have a recorded backtrace') do |name|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl.backtrace.to_s).not_to be_empty
end

Then('the download for bank {string} should have a recorded log') do |name|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id).order(Sequel.desc(:id)).first
  expect(dl.log.to_s).not_to be_empty
end

Then('the download for bank {string} on {string} should have status {string}') do |name, date, status|
  bank = Bank.find(name: name)
  dl   = Download.where(bank_id: bank.id, date: to_date(date)).first
  expect(dl.status).to eq status
end

Then('there should be {int} download(s) for bank {string} on {string}') do |count, name, date|
  bank = Bank.find(name: name)
  expect(Download.where(bank_id: bank.id, date: to_date(date)).count).to eq count
end

Then('the SFTP helper should have been called {int} time(s)') do |count|
  expect(@sftp_calls.size).to eq count
end

Then('every SFTP call used download_dir {string}') do |dir|
  dirs = @sftp_calls.map { |c| c[:download_dir] }
  expect(dirs).not_to be_empty
  expect(dirs.uniq).to eq [dir]
end

Then('every SFTP call used timeout {int}') do |timeout|
  timeouts = @sftp_calls.map { |c| c[:timeout] }
  expect(timeouts).not_to be_empty
  expect(timeouts.uniq).to eq [timeout]
end

# Idempotent enqueue
When('I enqueue downloads for {string} again') do |date|
  @count_before = Download.where(date: to_date(date)).count
  DownloadJob.enqueue(date: to_date(date))
  @count_after = Download.where(date: to_date(date)).count
end

Then('the download count should be unchanged') do
  expect(@count_after).to eq @count_before
end
