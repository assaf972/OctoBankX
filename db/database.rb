require 'sequel'
require 'logger'

module OctoBankX
  def self.db
    @db ||= connect_db
  end

  def self.connect_db
    db_path = ENV.fetch('DATABASE_URL', "sqlite://#{File.expand_path('../../octobankx.db', __FILE__)}")
    db = Sequel.connect(db_path)
    db.loggers << Logger.new($stdout) if ENV['DB_LOG'] == '1'
    db
  end

  def self.migrate!
    Sequel.extension :migration
    migrations_dir = File.expand_path('../migrations', __FILE__)
    Sequel::Migrator.run(db, migrations_dir)
  end
end
