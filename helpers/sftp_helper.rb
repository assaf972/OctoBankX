require 'net/sftp'
require 'fileutils'
require 'zip'
require 'logger'

module SftpHelper
  LOG = Logger.new($stdout)

  ZIP_MAGIC = "PK\x03\x04".b.freeze

  # Downloads a bank's statement file over SFTP for the given date.
  #
  # Full process:
  #   1. Log in to the bank's SFTP server.
  #   2. Download the statement file to <download_dir>/<bank_slug>/.
  #   3. Delete the file from the SFTP server.
  #   4. If the downloaded file is a ZIP archive, extract its contents into
  #      the bank's target_folder (falling back to the local download dir).
  #
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
      LOG.info("Downloaded #{remote_path} -> #{local_path}")

      # Remove the file from the server once it is safely downloaded.
      sftp.remove!(remote_path)
      LOG.info("Deleted remote file #{remote_path}")
    end

    # If the file is a ZIP archive, extract it into the bank's target folder.
    if zip?(local_path)
      target = target_folder_for(bank, local_dir)
      names  = extract_zip(local_path, target)
      LOG.info("Extracted #{names.size} file(s) from #{local_path} -> #{target}")
    end

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

  # The folder a bank's archives are extracted into. Uses the bank's
  # configured target_folder, falling back to the local download directory.
  def self.target_folder_for(bank, fallback)
    tf = bank.respond_to?(:target_folder) ? bank.target_folder : nil
    tf.to_s.strip.empty? ? fallback : tf
  end

  # Detects a ZIP archive by its magic header (works regardless of extension).
  def self.zip?(path)
    return true if File.extname(path).casecmp('.zip').zero?
    return false unless File.file?(path)

    File.open(path, 'rb') { |f| f.read(4) } == ZIP_MAGIC
  rescue StandardError
    false
  end

  # Extracts every file entry in the archive into dest_dir, overwriting
  # existing files. Returns the list of extracted entry names.
  def self.extract_zip(zip_path, dest_dir)
    FileUtils.mkdir_p(dest_dir)
    base      = File.expand_path(dest_dir)
    extracted = []

    Zip::File.open(zip_path) do |archive|
      archive.each do |entry|
        next if entry.directory?

        dest = File.expand_path(File.join(dest_dir, entry.name))
        # Guard against zip-slip: never write outside the target folder.
        unless dest == base || dest.start_with?("#{base}#{File::SEPARATOR}")
          raise "Refusing to extract entry outside target folder: #{entry.name}"
        end

        FileUtils.mkdir_p(File.dirname(dest))
        File.binwrite(dest, entry.get_input_stream.read)
        extracted << entry.name
      end
    end

    extracted
  end
end
