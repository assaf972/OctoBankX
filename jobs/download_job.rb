require_relative '../models/bank'
require_relative '../models/download'
require_relative '../models/setting'
require_relative '../helpers/sftp_helper'
require 'logger'

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

    LOG.info("DownloadJob: starting download id=#{download.id} bank=#{bank.name}")
    download.mark_running!

    file_path = SftpHelper.download(
      bank:         bank,
      date:         download.date,
      download_dir: download_dir,
      timeout:      timeout
    )

    download.mark_success!(file_path)
    LOG.info("DownloadJob: success id=#{download.id} file=#{file_path}")
  rescue StandardError => e
    download.mark_failed!(e.message)
    LOG.error("DownloadJob: failed id=#{download.id} error=#{e.message}")
  end
end
