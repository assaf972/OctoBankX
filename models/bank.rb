require_relative '../db/database'

class Bank < Sequel::Model(OctoBankX.db)
  one_to_many :accounts
  one_to_many :downloads

  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  def validate
    super
    validates_presence [:name, :sftp_host]
    validates_unique :name
    validates_integer :sftp_port
    validates_includes (1..65535), :sftp_port
  end

  def sftp_url
    "sftp://#{sftp_host}:#{sftp_port}#{sftp_remote_path}"
  end
end
