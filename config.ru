require_relative 'db/database'
require_relative 'app'

# Run database migrations on startup
OctoBankX.migrate!

# Start the daily download scheduler (disabled in test env)
unless ENV['RACK_ENV'] == 'test'
  require 'rufus-scheduler'
  require_relative 'jobs/download_job'

  scheduler = Rufus::Scheduler.new
  schedule  = ENV.fetch('JOB_SCHEDULE', '0 6 * * *')

  scheduler.cron(schedule) do
    DownloadJob.run(date: Date.today)
  end
end

run OctoBankXApp
