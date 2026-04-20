require_relative '../models/account'
require_relative '../models/bank'
require_relative '../models/download'
require_relative '../models/setting'
require_relative '../helpers/sftp_helper'
require 'logger'

class DownloadJob
  LOG = Logger.new($stdout)

  # Enqueues one Download record per account for the given date (default today).
  # Skips accounts that already have a download record for that date.
  def self.enqueue(date: Date.today)
    accounts = Account.all
    LOG.info("DownloadJob: enqueuing #{accounts.size} account(s) for #{date}")

    accounts.each do |account|
      next if Download.where(account_id: account.id, date: date).count > 0

      Download.create(
        account_id: account.id,
        bank_id:    account.bank_id,
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
    account = download.account
    bank    = download.bank

    LOG.info("DownloadJob: starting download id=#{download.id} account=#{account.account_no}")
    download.mark_running!

    file_path = SftpHelper.download(
      account:      account,
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
