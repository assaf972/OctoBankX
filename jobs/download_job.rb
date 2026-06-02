require_relative '../models/bank'
require_relative '../models/download'
require_relative '../models/setting'
require_relative '../models/log_event'
require_relative '../helpers/sftp_helper'
require 'logger'
require 'time'

class DownloadJob
  LOG = Logger.new($stdout)

  # Enqueues one Download record per bank for the given date (default today).
  # Skips banks that already have a download record for that date.
  def self.enqueue(date: Date.today)
    banks = Bank.all
    LOG.info("DownloadJob: enqueuing #{banks.size} bank(s) for #{date}")

    banks.each do |bank|
      next if Download.where(bank_id: bank.id, date: date).count > 0

      Download.create(
        bank_id:    bank.id,
        date:       date,
        status:     'pending',
        created_at: Time.now
      )
    end
  end

  # Runs all pending downloads. Designed to be called from the scheduler.
  def self.run(date: Date.today)
    enqueue(date: date)

    download_dir = Setting['download_dir'] || '/tmp/octobankx/downloads'
    sftp_timeout = (Setting['sftp_timeout'] || 30).to_i

    pending = Download.where(status: 'pending', date: date).all
    LOG.info("DownloadJob: processing #{pending.size} pending download(s)")

    pending.each { |dl| process(dl, download_dir: download_dir, timeout: sftp_timeout) }
  end

  def self.process(download, download_dir:, timeout:)
    bank = download.bank
    log  = []
    log << "[#{Time.now.iso8601}] Starting job id=#{download.id} bank=#{bank&.name} date=#{download.date}"

    LOG.info("DownloadJob: starting download id=#{download.id} bank=#{bank&.name}")
    # Mark running and clear any state from a previous attempt.
    download.update(status: 'running', started_at: Time.now,
                    error_message: nil, backtrace: nil, log: log.join("\n"))

    log << "[#{Time.now.iso8601}] Connecting to #{bank&.sftp_host}:#{bank&.sftp_port} as #{bank&.sftp_username}"

    file_path = SftpHelper.download(
      bank:         bank,
      date:         download.date,
      download_dir: download_dir,
      timeout:      timeout
    )

    log << "[#{Time.now.iso8601}] Downloaded to #{file_path}"
    log << "[#{Time.now.iso8601}] Completed successfully"
    # Persist final state atomically: status, file path, timing and log.
    download.update(status: 'success', file_path: file_path,
                    completed_at: Time.now, log: log.join("\n"))
    LOG.info("DownloadJob: success id=#{download.id} file=#{file_path}")
  rescue StandardError => e
    log << "[#{Time.now.iso8601}] FAILED: #{e.class}: #{e.message}"
    # Persist status, error message AND the full exception backtrace together.
    download.update(
      status:        'failed',
      error_message: e.message,
      backtrace:     format_backtrace(e),
      completed_at:  Time.now,
      log:           log.join("\n")
    )
    LogEvent.exception(e, download: download,
                       message: "Download failed for #{bank&.name} on #{download.date}")
    LOG.error("DownloadJob: failed id=#{download.id} error=#{e.message}")
  end

  # Builds a full backtrace string, following the exception's cause chain so
  # the original failure (not just SftpHelper's re-raise) is captured.
  def self.format_backtrace(error)
    lines = []
    current = error
    until current.nil?
      header = current.equal?(error) ? "#{current.class}: #{current.message}"
                                     : "Caused by: #{current.class}: #{current.message}"
      lines << header
      lines.concat(Array(current.backtrace))
      current = current.cause
      lines << '' unless current.nil?
    end
    lines.join("\n")
  end

  # Resets a finished/failed download and processes it again (synchronously).
  def self.rerun(download)
    download_dir = Setting['download_dir'] || '/tmp/octobankx/downloads'
    timeout      = (Setting['sftp_timeout'] || 30).to_i

    download.update(
      status:        'pending',
      started_at:    nil,
      completed_at:  nil,
      error_message: nil,
      file_path:     nil,
      log:           nil,
      backtrace:     nil
    )
    process(download, download_dir: download_dir, timeout: timeout)
    download
  end
end
