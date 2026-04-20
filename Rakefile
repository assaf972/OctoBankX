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

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)
task default: :spec
