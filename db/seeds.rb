require_relative 'database'
require_relative '../models/bank'
require_relative '../models/download'
require_relative '../models/setting'

OctoBankX.migrate!

DB = OctoBankX.db

puts '── Seeding OctoBankX ──────────────────────────────────────────'

# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------
def find_or_create_bank(attrs)
  Bank.find(name: attrs[:name]) || Bank.create(attrs.merge(created_at: Time.now, updated_at: Time.now))
end

ERROR_MESSAGES = [
  'SFTP authentication failed: incorrect username or password',
  'SFTP connection refused — host unreachable',
  'SFTP status error: No such file or directory (code 2)',
  'Network timeout after 30 seconds',
  'SSH handshake failed: host key verification error',
  'Remote path /statements does not exist',
  'SFTP quota exceeded on remote server',
  'ZIP extraction failed: corrupt archive',
  'File not found on remote server for requested date',
].freeze

def random_duration = 2.0 + rand * 18.0   # 2–20 s
def random_error    = ERROR_MESSAGES.sample
def business_day?(d) = ![0, 6].include?(d.wday)   # skip Sat/Sun

# ----------------------------------------------------------------
# File-name patterns per bank (based on banks-files-info document)
# ----------------------------------------------------------------
# Each bank has a different file naming convention:
#   Discount / Mercantile: D<YYYYMMDD>_<code>.csv
#   Hapoalim: ZIP vault → extracted CSV: HP_<YYYYMMDD>_<seq>.csv
#   Mizrahi:  MZ_<YYYYMMDD>.csv (date in filename, daily run)
#   FIBI:     statement_<YYYYMMDD>.csv (different names, same extension)
#   Leumi:    leumi_<YYYYMMDD>_<source>.csv (multiple source files)
#   Psagot:   psagot_broker_<YYYYMMDD>.csv  (arrives via email)
#   Meitav:   meitav_<YYYYMMDD>.csv         (arrives via email)
#   Excellence: exc_<YYYYMMDD>.csv          (arrives via email)

BANK_FILE_PATTERNS = {
  'בנק דיסקונט'             => ->(date) { "D#{date.strftime('%Y%m%d')}_DISC001.csv" },
  'בנק הפועלים'            => ->(date) { "HP_#{date.strftime('%Y%m%d')}_001.csv" },
  'בנק מזרחי טפחות'     => ->(date) { "MZ_#{date.strftime('%Y%m%d')}.csv" },
  'הבנק הבינלאומי הראשון' => ->(date) { "statement_#{date.strftime('%Y%m%d')}.csv" },
  'בנק לאומי'               => ->(date) { "leumi_#{date.strftime('%Y%m%d')}_main.csv" },
  'פסגות חבר בורסה'       => ->(date) { "psagot_broker_#{date.strftime('%Y%m%d')}.csv" },
  'מיטב חבר בורסה'        => ->(date) { "meitav_#{date.strftime('%Y%m%d')}.csv" },
  'אקסלנס חבר בורסה'     => ->(date) { "exc_#{date.strftime('%Y%m%d')}.csv" },
}.freeze

# ----------------------------------------------------------------
# Banks (5 original + 3 broker firms from bank-files-info)
# ----------------------------------------------------------------
puts "\n→ Banks"

banks = [
  # Banks
  { name: 'בנק לאומי',               sftp_host: 'sftp.leumi.co.il',            sftp_port: 22,   sftp_remote_path: '/statements',          sftp_username: 'octobankx_leumi',   sftp_password: 'lm!s3cure#', parser: 'LeumiParser',    ruler: "date:0\ndescription:1\nreference:2\ndebit:3\ncredit:4\nbalance:5\ncurrency:6\nvalue_date:7",                                                                                             target_folder: 'D:\DANEL\LEUMI' },
  { name: 'בנק הפועלים',            sftp_host: 'sftp.bankhapoalim.co.il',      sftp_port: 22,   sftp_remote_path: '/outgoing/statements', sftp_username: 'octobankx_hap',     sftp_password: 'hp@dl2024',  parser: 'PoalimParser',   ruler: "date:0:10\nvalue_date:10:10\nreference:20:12\ndescription:32:30\ndebit:62:15\ncredit:77:15\nbalance:92:15\ncurrency:107:3", target_folder: 'D:\DANEL\POALIM' },
  { name: 'בנק מזרחי טפחות',     sftp_host: 'sftp.mizrahi-tefahot.co.il',   sftp_port: 2222, sftp_remote_path: '/daily',               sftp_username: 'octobankx_mz',      sftp_password: 'mz#d@ily',                                                                                                                                                                          target_folder: 'D:\DANEL\MIZRAHI' },
  { name: 'בנק דיסקונט',            sftp_host: 'sftp.discountbank.co.il',      sftp_port: 22,   sftp_remote_path: '/exports',             sftp_username: 'octobankx_disc',    sftp_password: 'disc0unt!',  parser: 'DiscountParser', ruler: "date:0\nvalue_date:1\nreference:2\ndescription:3\namount:4\nbalance:5\ncurrency:6",                                                                                                   target_folder: 'D:\DANEL\DISCOUNT' },
  { name: 'הבנק הבינלאומי הראשון', sftp_host: 'sftp.fibi.co.il',             sftp_port: 22,   sftp_remote_path: '/statements/daily',    sftp_username: 'octobankx_fibi',    sftp_password: 'f1bi$tmt',   parser: 'FibiParser',     ruler: "date:0\nvalue_date:1\ndescription:2\nreference:3\ndebit:4\ncredit:5\nbalance:6\ncurrency:7",                                                                                             target_folder: 'D:\DANEL\FIBI' },
  # Broker firms (חברי בורסה — files arrive via email / dedicated SFTP)
  { name: 'פסגות חבר בורסה',       sftp_host: 'sftp.psagot.co.il',            sftp_port: 22,   sftp_remote_path: '/broker/daily',        sftp_username: 'octobankx_psagot',  sftp_password: 'ps@g0t!',    target_folder: 'D:\DANEL\PSAGOT' },
  { name: 'מיטב חבר בורסה',        sftp_host: 'sftp.meitav.co.il',            sftp_port: 22,   sftp_remote_path: '/reports',             sftp_username: 'octobankx_meitav',  sftp_password: 'me1tav#r',   target_folder: 'D:\DANEL\MEITAV' },
  { name: 'אקסלנס חבר בורסה',     sftp_host: 'sftp.excellence.co.il',        sftp_port: 22,   sftp_remote_path: '/statements',          sftp_username: 'octobankx_exc',     sftp_password: 'exc3l!nce',  target_folder: 'D:\DANEL\EXCELLENCE' },
].map { |attrs| find_or_create_bank(attrs) }

puts "   #{banks.size} banks ready"

# ----------------------------------------------------------------
# Downloads — 60 business days of history per bank
# ----------------------------------------------------------------
puts "\n→ Downloads (history + today)"

download_dir = '/var/octobankx/downloads'
today        = Date.today
history_days = (1..84).map { |n| today - n }.select { |d| business_day?(d) }.first(60)

inserted = 0

history_days.each do |date|
  banks.each do |bank|
    next if Download.where(bank_id: bank.id, date: date).count > 0

    # Weighted status distribution: ~80% success, ~12% failed, ~8% pending
    roll = rand(100)
    status = case roll
             when  0..79 then 'success'
             when 80..91 then 'failed'
             else              'pending'
             end

    job_time    = Time.new(date.year, date.month, date.day, 6, 0, 0) + rand(120)
    duration    = random_duration
    started_at  = job_time + rand(5)
    completed_at = started_at + duration

    # Use bank-specific file naming pattern
    file_pattern = BANK_FILE_PATTERNS[bank.name]
    file_name    = file_pattern ? file_pattern.call(date) : "#{date.strftime('%Y%m%d')}_#{bank.name.gsub(/\s+/, '_').downcase}.csv"
    bank_slug    = bank.name.gsub(/\s+/, '_').downcase

    attrs = {
      bank_id:    bank.id,
      date:       date,
      status:     status,
      created_at: job_time,
    }

    case status
    when 'success'
      attrs.merge!(
        started_at:   started_at,
        completed_at: completed_at,
        file_path:    "#{download_dir}/#{bank_slug}/#{file_name}"
      )
    when 'failed'
      attrs.merge!(
        started_at:    started_at,
        completed_at:  completed_at,
        error_message: random_error
      )
    end

    Download.create(attrs)
    inserted += 1
  end
end

puts "   #{inserted} historical download records inserted"

# ----------------------------------------------------------------
# Today's downloads — simulate a morning run in progress
# ----------------------------------------------------------------
puts "\n→ Today's downloads"
today_inserted = 0

banks.each_with_index do |bank, idx|
  next if Download.where(bank_id: bank.id, date: today).count > 0

  run_time = Time.new(today.year, today.month, today.day, 6, 0, 0) + idx * 8

  file_pattern = BANK_FILE_PATTERNS[bank.name]
  file_name    = file_pattern ? file_pattern.call(today) : "#{today.strftime('%Y%m%d')}_#{bank.name.gsub(/\s+/, '_').downcase}.csv"
  bank_slug    = bank.name.gsub(/\s+/, '_').downcase

  # Spread today's records across statuses to make the UI interesting
  status, extra = case idx % 5
                  when 0 then ['success', { started_at: run_time,        completed_at: run_time + random_duration,
                                             file_path: "#{download_dir}/#{bank_slug}/#{file_name}" }]
                  when 1 then ['failed',  { started_at: run_time,        completed_at: run_time + random_duration,
                                             error_message: random_error }]
                  when 2 then ['running', { started_at: run_time }]
                  when 3 then ['success', { started_at: run_time,        completed_at: run_time + random_duration,
                                             file_path: "#{download_dir}/#{bank_slug}/#{file_name}" }]
                  else        ['pending', {}]
                  end

  Download.create({
    bank_id:    bank.id,
    date:       today,
    status:     status,
    created_at: run_time,
  }.merge(extra))

  today_inserted += 1
end

puts "   #{today_inserted} today's records inserted"

# ----------------------------------------------------------------
# Settings — upsert to add/refresh all keys
# ----------------------------------------------------------------
puts "\n→ Settings"

[
  { key: 'download_dir',    value: '/var/octobankx/downloads',  description: 'Local directory where downloaded bank statements are stored' },
  { key: 'sftp_timeout',    value: '30',                         description: 'SFTP connection timeout in seconds' },
  { key: 'job_schedule',    value: '0 6 * * 1-5',               description: 'Cron expression for daily download job (business days, 6am)' },
  { key: 'retention_days',  value: '90',                         description: 'Number of days to keep download history' },
  { key: 'alert_email',     value: 'ops@octobankx.local',        description: 'Email address for failure alerts' },
  { key: 'max_retries',     value: '3',                          description: 'Maximum SFTP retry attempts per bank per day' },
  { key: 'notify_on_fail',  value: 'true',                       description: 'Send alert email when a download fails' },
].each do |s|
  existing = Setting.find(key: s[:key])
  if existing
    existing.update(description: s[:description], updated_at: Time.now)
  else
    Setting.create(key: s[:key], value: s[:value], description: s[:description], updated_at: Time.now)
  end
end

puts "   #{Setting.count} settings in place"

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
puts "\n── Seed complete ───────────────────────────────────────────────"
puts "   Banks:     #{Bank.count}"
puts "   Downloads: #{Download.count} total"
puts "              #{Download.where(status: 'success').count} success"
puts "              #{Download.where(status: 'failed').count}  failed"
puts "              #{Download.where(status: 'running').count}  running"
puts "              #{Download.where(status: 'pending').count}  pending"
puts "   Settings:  #{Setting.count}"
puts "────────────────────────────────────────────────────────────────"
