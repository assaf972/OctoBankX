require 'sequel'
require_relative 'db/database'

namespace :db do
  desc 'Run all pending migrations'
  task :migrate do
    OctoBankX.migrate!
    puts 'Migrations complete.'
  end

  desc 'Seed the database with sample data'
  task :seed do
    load File.expand_path('db/seeds.rb', __dir__)
  end

  desc 'Migrate then seed (first-time setup)'
  task setup: %i[migrate seed]

  desc 'Drop, recreate, and reseed the database'
  task :reset do
    db_file = File.expand_path('octobankx.db', __dir__)
    File.delete(db_file) if File.exist?(db_file)
    OctoBankX.instance_variable_set(:@db, nil)
    OctoBankX.migrate!
    puts 'Migrations complete.'
    load File.expand_path('db/seeds.rb', __dir__)
  end
end

namespace :jobs do
  desc 'Run the download job for today'
  task :run do
    require_relative 'jobs/download_job'
    DownloadJob.run(date: Date.today)
  end
end

namespace :sftp do
  # Local end-to-end SFTP test. Boots a disposable SFTP server in Docker,
  # drops a fake statement file matching what the app expects, creates a
  # test bank pointing at it, and runs ONE real download through the actual
  # SftpHelper / DownloadJob code (no mocking).
  CONTAINER  = 'octosftp-test'.freeze
  SFTP_USER  = 'testuser'.freeze
  SFTP_PASS  = 'testpass'.freeze
  SFTP_PORT  = 2222
  BANK_NAME  = 'Test SFTP Bank'.freeze
  HOST_DIR   = '/tmp/octobankx-sftp-test/statements'.freeze
  DL_DIR     = '/tmp/octobankx-sftp-test/downloads'.freeze

  desc 'Run a single real SFTP download against a local Docker SFTP server'
  task :test_local do
    require 'socket'
    require 'fileutils'
    require_relative 'jobs/download_job'

    abort 'Docker is not installed. Install Docker Desktop first.' unless system('command -v docker > /dev/null 2>&1')
    unless system('docker info > /dev/null 2>&1')
      abort 'Docker daemon is not running. Start Docker Desktop and retry.'
    end

    date = Date.today

    # The app expects the remote file named YYYYMMDD_<bank_slug>.csv
    # where bank_slug = bank.name downcased with spaces -> underscores.
    remote_filename = SftpHelper.statement_filename(
      Struct.new(:name).new(BANK_NAME), date
    )

    FileUtils.mkdir_p(HOST_DIR)
    FileUtils.mkdir_p(DL_DIR)
    File.write(
      File.join(HOST_DIR, remote_filename),
      "date,balance,description\n#{date.strftime('%Y-%m-%d')},1000.00,Test statement line\n"
    )
    puts "Created fake statement: #{File.join(HOST_DIR, remote_filename)}"

    # (Re)start a disposable SFTP server. atmoz/sftp chroots the user to
    # /home/<user>, so the mounted /statements dir is reachable at /statements.
    system("docker rm -f #{CONTAINER} > /dev/null 2>&1")
    boot = system(
      "docker run -d --name #{CONTAINER} -p #{SFTP_PORT}:22 " \
      "-v #{HOST_DIR}:/home/#{SFTP_USER}/statements " \
      "atmoz/sftp #{SFTP_USER}:#{SFTP_PASS}:::statements > /dev/null"
    )
    abort 'Failed to start the SFTP container.' unless boot

    print 'Waiting for SFTP server to accept connections'
    ready = false
    30.times do
      begin
        TCPSocket.new('localhost', SFTP_PORT).close
        ready = true
        break
      rescue StandardError
        print '.'
        sleep 1
      end
    end
    puts ''
    abort 'SFTP server did not become ready in time.' unless ready
    sleep 2 # give sshd a moment to finish generating host keys

    # Make sure the schema exists, then create/refresh the test bank.
    OctoBankX.migrate!

    bank = Bank.find(name: BANK_NAME) || Bank.new(name: BANK_NAME)
    bank.set(
      sftp_host:        'localhost',
      sftp_port:        SFTP_PORT,
      sftp_username:    SFTP_USER,
      sftp_password:    SFTP_PASS,
      sftp_remote_path: '/statements'
    )
    bank.save_changes
    puts "Test bank ready: id=#{bank.id} #{bank.sftp_url}"

    # Single download for this bank/date through the real job + helper.
    Download.where(bank_id: bank.id, date: date).delete
    download = Download.create(
      bank_id:    bank.id,
      date:       date,
      status:     'pending',
      created_at: Time.now
    )

    puts "\nRunning download id=#{download.id} ..."
    DownloadJob.process(download, download_dir: DL_DIR, timeout: 15)

    download.refresh
    puts "\n=== Result ==="
    puts "status:    #{download.status}"
    puts "file_path: #{download.file_path}"
    puts "error:     #{download.error_message}" if download.error_message
    if download.success? && download.file_path && File.exist?(download.file_path)
      puts "\nDownloaded file contents:"
      puts File.read(download.file_path)
      puts "\n✅ End-to-end SFTP download works."
    else
      puts "\n❌ Download did not succeed. See error above."
    end

    puts "\nWhen finished, clean up with: rake sftp:clean"
  end

  desc 'Tear down the local SFTP test container and temp files'
  task :clean do
    require 'fileutils'
    system("docker rm -f #{CONTAINER} > /dev/null 2>&1")
    FileUtils.rm_rf('/tmp/octobankx-sftp-test')
    puts 'Removed test container and /tmp/octobankx-sftp-test.'
  end
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

begin
  require 'cucumber/rake/task'
  Cucumber::Rake::Task.new(:features) do |t|
    t.cucumber_opts = 'features --format pretty'
  end
rescue LoadError
  # cucumber not installed (e.g. production) — skip the task
end

desc 'Run both RSpec and Cucumber suites'
task test: %i[spec features]

task default: :spec
