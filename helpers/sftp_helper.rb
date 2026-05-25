require 'net/sftp'
require 'fileutils'
require 'logger'

module SftpHelper
  LOG = Logger.new($stdout)

  # Downloads a file from the bank's SFTP server for the given date.
  # Returns the local file path on success, raises on failure.
  def self.download(bank:, date:, download_dir:, timeout: 30)
    bank_slug = bank.name.gsub(/\s+/, '_')
    local_dir = File.join(download_dir, bank_slug)
    FileUtils.mkdir_p(local_dir)

    remote_filename = statement_filename(bank, date)
    remote_path     = File.join(bank.sftp_remote_path.to_s, remote_filename)
    local_path      = File.join(local_dir, remote_filename)

    LOG.info("SFTP connect #{bank.sftp_host}:#{bank.sftp_port} as #{bank.sftp_username}")

    Net::SFTP.start(
      bank.sftp_host,
      bank.sftp_username,
      password:            bank.sftp_password,
      port:                bank.sftp_port || 22,
      timeout:             timeout.to_i,
      non_interactive:     true,
      auth_methods:        %w[password publickey]
    ) do |sftp|
      sftp.download!(remote_path, local_path)
    end

    LOG.info("Downloaded #{remote_path} -> #{local_path}")
    local_path
  rescue Net::SFTP::StatusException => e
    raise "SFTP status error: #{e.description} (code #{e.code})"
  rescue Net::SSH::AuthenticationFailed => e
    raise "SFTP authentication failed for #{bank.sftp_username}@#{bank.sftp_host}: #{e.message}"
  rescue Errno::ECONNREFUSED, SocketError => e
    raise "SFTP connection failed to #{bank.sftp_host}: #{e.message}"
  rescue StandardError => e
    raise "SFTP error: #{e.message}"
  end

  # Generates expected remote filename: YYYYMMDD_<bank_slug>.csv
  def self.statement_filename(bank, date)
    bank_slug = bank.name.gsub(/\s+/, '_').downcase
    "#{date.strftime('%Y%m%d')}_#{bank_slug}.csv"
  end
end
