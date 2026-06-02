# Steps for the Job detail page and its rerun / kill / delete actions.

Given('a failed job for bank {string} exists') do |name|
  bank = find_or_create_bank(name)
  @job = Download.create(
    bank_id:       bank.id,
    date:          Date.today,
    status:        'failed',
    error_message: 'SFTP authentication failed for user@host',
    log:           "[t0] Starting job\n[t1] Connecting to host\n[t2] FAILED: SFTP authentication failed",
    backtrace:     "helpers/sftp_helper.rb:38:in `download'\njobs/download_job.rb:50:in `process'",
    started_at:    Time.now - 5,
    completed_at:  Time.now,
    created_at:    Time.now
  )
end

Given('a running job for bank {string} exists') do |name|
  bank = find_or_create_bank(name)
  @job = Download.create(bank_id: bank.id, date: Date.today, status: 'running',
                         started_at: Time.now, created_at: Time.now)
end

Given('a successful job for bank {string} exists') do |name|
  bank = find_or_create_bank(name)
  @job = Download.create(bank_id: bank.id, date: Date.today, status: 'success',
                         file_path: '/tmp/stmt.csv', started_at: Time.now - 3,
                         completed_at: Time.now, created_at: Time.now)
end

When('I open that job from the jobs list') do
  visit '/jobs'
  first("a[href='/jobs/#{@job.id}']").click
end

When('I open that job detail page') do
  visit "/jobs/#{@job.id}"
end

Then('I should see a code block') do
  expect(page).to have_css('pre.code-block')
end

Then('the job should now have status {string}') do |status|
  expect(@job.refresh.status).to eq status
end

Then('the job should no longer exist') do
  expect(Download[@job.id]).to be_nil
end
