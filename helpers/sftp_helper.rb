require 'net/sftp'
require 'fileutils'
require 'logger'

module SftpHelper
  LOG = Logger.new($stdout)

  # Downloads a file from the bank's SFTP server for the given account and date.
  # Returns the local file path on success, raises on failure.
  def self.download(account:, bank:, date:, download_dir:, timeout: 30)
    local_dir = File.join(download_dir, bank.name.gsub(/\s+/, '_'), account.account_no)
    FileUtils.mkdir_p(local_dir)

    remote_filename = statement_filename(account, date)
    remote_path     = File.join(bank.sftp_remote_path.to_s, remote_filename)
    local_path      = File.join(local_dir, remote_filename)

    LOG.info("SFTP connect #{bank.sftp_host}:#{bank.sftp_port} as #{account.sftp_username}")

    Net::SFTP.start(
      bank.sftp_host,
      account.sftp_username,
      password:            account.sftp_password,
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
    raise "SFTP authentication failed for #{account.sftp_username}@#{bank.sftp_host}: #{e.message}"
  rescue Errno::ECONNREFUSED, SocketError => e
    raise "SFTP connection failed to #{bank.sftp_host}: #{e.message}"
  rescue StandardError => e
    raise "SFTP error: #{e.message}"
  end

  # Generates expected remote filename: YYYYMMDD_<account_no>.csv
  def self.statement_filename(account, date)
    "#{date.strftime('%Y%m%d')}_#{account.account_no}.csv"
  end
end
