require_relative 'database'
require_relative '../models/bank'
require_relative '../models/account'
require_relative '../models/download'
require_relative '../models/setting'
require_relative '../models/api_call'

OctoBankX.migrate!

DB = OctoBankX.db

puts '── Seeding OctoBankX ──────────────────────────────────────────'

# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------
def find_or_create_bank(attrs)
  Bank.find(name: attrs[:name]) || Bank.create(attrs.merge(created_at: Time.now, updated_at: Time.now))
end

def find_or_create_account(attrs)
  Account.find(account_no: attrs[:account_no]) ||
    Account.create(attrs.merge(created_at: Time.now, updated_at: Time.now))
end

ERROR_MESSAGES = [
  'SFTP authentication failed: incorrect username or password',
  'SFTP connection refused — host unreachable',
  'SFTP status error: No such file or directory (code 2)',
  'Network timeout after 30 seconds',
  'SSH handshake failed: host key verification error',
  'Remote path /statements does not exist',
  'SFTP quota exceeded on remote server',
].freeze

def random_duration = 2.0 + rand * 18.0   # 2–20 s
def random_error    = ERROR_MESSAGES.sample
def business_day?(d) = ![0, 6].include?(d.wday)   # skip Sat/Sun

# ----------------------------------------------------------------
# Banks
# ----------------------------------------------------------------
puts "\n→ Banks"

banks = [
  { name: 'בנק לאומי',               sftp_host: 'sftp.leumi.co.il',            sftp_port: 22,   sftp_remote_path: '/statements',          parser: 'LeumiParser',    ruler: "date:0\ndescription:1\nreference:2\ndebit:3\ncredit:4\nbalance:5\ncurrency:6\nvalue_date:7" },
  { name: 'בנק הפועלים',            sftp_host: 'sftp.bankhapoalim.co.il',      sftp_port: 22,   sftp_remote_path: '/outgoing/statements', parser: 'PoalimParser',   ruler: "date:0:10\nvalue_date:10:10\nreference:20:12\ndescription:32:30\ndebit:62:15\ncredit:77:15\nbalance:92:15\ncurrency:107:3" },
  { name: 'בנק מזרחי טפחות',     sftp_host: 'sftp.mizrahi-tefahot.co.il',   sftp_port: 2222, sftp_remote_path: '/daily' },
  { name: 'בנק דיסקונט',            sftp_host: 'sftp.discountbank.co.il',      sftp_port: 22,   sftp_remote_path: '/exports',             parser: 'DiscountParser', ruler: "date:0\nvalue_date:1\nreference:2\ndescription:3\namount:4\nbalance:5\ncurrency:6" },
  { name: 'הבנק הבינלאומי הראשון', sftp_host: 'sftp.fibi.co.il',             sftp_port: 22,   sftp_remote_path: '/statements/daily',    parser: 'FibiParser',     ruler: "date:0\nvalue_date:1\ndescription:2\nreference:3\ndebit:4\ncredit:5\nbalance:6\ncurrency:7" },
].map { |attrs| find_or_create_bank(attrs) }

leumi, hapoalim, mizrahi, discount, fibi = banks
puts "   #{banks.size} banks ready"

# ----------------------------------------------------------------
# Accounts
# ----------------------------------------------------------------
puts "\n→ Accounts"

accounts = [
  # בנק לאומי
  {
    name: 'אלדן השכרת רכב — תפעול',       account_no: 'IL-LM-0012345', bank: leumi,
    branch: 'תל אביב — דיזנגוף',           currency: 'ש"ח', balance: 428_500.00,  balance_date: Date.today - 1,
    sftp_username: 'eldan_leumi',          sftp_password: 'p@ssw0rd!'
  },
  {
    name: 'קבוצת שטראוס — קופה',           account_no: 'IL-LM-0098712', bank: leumi,
    branch: 'פתח תקווה — העצמאות',         currency: 'דולר', balance: 1_250_000.00, balance_date: Date.today - 1,
    sftp_username: 'strauss_leumi',        sftp_password: 'str@uss#24'
  },
  # בנק הפועלים
  {
    name: 'אוסם השקעות — שכר',             account_no: 'IL-HP-0055678', bank: hapoalim,
    branch: 'רחובות — הרצל',               currency: 'ש"ח', balance: 87_300.50,   balance_date: Date.today - 1,
    sftp_username: 'osem_hap',             sftp_password: '0s3m$ftp'
  },
  {
    name: 'צ\'ק פוינט תוכנה — אירו',       account_no: 'IL-HP-0200034', bank: hapoalim,
    branch: 'תל אביב — עזריאלי',           currency: 'אירו', balance: 3_780_000.00, balance_date: Date.today - 2,
    sftp_username: 'chkpt_eur',            sftp_password: 'chkp01!'
  },
  # בנק מזרחי טפחות
  {
    name: 'תנובה חלב — חשבון ראשי',        account_no: 'IL-MZ-0031199', bank: mizrahi,
    branch: 'רחובות — אזור תעשייה',        currency: 'ש"ח', balance: 560_200.00,  balance_date: Date.today - 1,
    sftp_username: 'tnuva_mz',             sftp_password: 'tn!uva99'
  },
  {
    name: 'טאואר סמיקונדקטור — דולר',      account_no: 'IL-MZ-0041002', bank: mizrahi,
    branch: 'מגדל העמק',                   currency: 'דולר', balance: 9_100_000.00, balance_date: Date.today - 1,
    sftp_username: 'tower_usd',            sftp_password: 't0wer#sc'
  },
  # בנק דיסקונט
  {
    name: 'אל על תעופה — תפעול',           account_no: 'IL-DC-0072345', bank: discount,
    branch: 'נתב"ג',                       currency: 'ש"ח', balance: 2_340_000.00, balance_date: Date.today - 1,
    sftp_username: 'elal_dc',              sftp_password: 'elal!2024'
  },
  {
    name: 'רפאל מערכות ביטחוניות',         account_no: 'IL-DC-0089001', bank: discount,
    branch: 'חיפה — נווה שאנן',            currency: 'דולר', balance: 15_600_000.00, balance_date: Date.today - 2,
    sftp_username: 'rafael_dc',            sftp_password: 'r@f@el$ec'
  },
  # הבנק הבינלאומי הראשון
  {
    name: 'אמדוקס טכנולוגיה — ש"ח',       account_no: 'IL-FI-0110456', bank: fibi,
    branch: 'רעננה — ההגנה',               currency: 'ש"ח', balance: 345_800.00,  balance_date: Date.today - 1,
    sftp_username: 'amdocs_ils',           sftp_password: 'amd0cs!'
  },
  {
    name: 'קבוצת כי"ל — קופת אירו',       account_no: 'IL-FI-0122789', bank: fibi,
    branch: 'תל אביב — הקריה',            currency: 'אירו', balance: 6_450_000.00, balance_date: Date.today - 1,
    sftp_username: 'icl_eur',              sftp_password: 'icl3ur#g'
  },
].map do |attrs|
  bank = attrs.delete(:bank)
  find_or_create_account(attrs.merge(bank_id: bank.id))
end

puts "   #{accounts.size} accounts ready"

# ----------------------------------------------------------------
# Downloads — 60 business days of history
# ----------------------------------------------------------------
puts "\n→ Downloads (history + today)"

download_dir = '/var/octobankx/downloads'
today        = Date.today
history_days = (1..84).map { |n| today - n }.select { |d| business_day?(d) }.first(60)

inserted = 0

history_days.each do |date|
  accounts.each do |account|
    next if Download.where(account_id: account.id, date: date).count > 0

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

    attrs = {
      account_id: account.id,
      bank_id:    account.bank_id,
      date:       date,
      status:     status,
      created_at: job_time,
    }

    case status
    when 'success'
      bank_slug    = account.bank.name.gsub(/\s+/, '_').downcase
      file_name    = "#{date.strftime('%Y%m%d')}_#{account.account_no}.csv"
      attrs.merge!(
        started_at:   started_at,
        completed_at: completed_at,
        file_path:    "#{download_dir}/#{bank_slug}/#{account.account_no}/#{file_name}"
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

accounts.each_with_index do |account, idx|
  next if Download.where(account_id: account.id, date: today).count > 0

  run_time = Time.new(today.year, today.month, today.day, 6, 0, 0) + idx * 8

  # Spread today's records across statuses to make the UI interesting
  status, extra = case idx % 5
                  when 0 then ['success', { started_at: run_time,        completed_at: run_time + random_duration,
                                             file_path: "#{download_dir}/#{account.bank.name.gsub(/\s+/,'_').downcase}/#{account.account_no}/#{today.strftime('%Y%m%d')}_#{account.account_no}.csv" }]
                  when 1 then ['failed',  { started_at: run_time,        completed_at: run_time + random_duration,
                                             error_message: random_error }]
                  when 2 then ['running', { started_at: run_time }]
                  when 3 then ['success', { started_at: run_time,        completed_at: run_time + random_duration,
                                             file_path: "#{download_dir}/#{account.bank.name.gsub(/\s+/,'_').downcase}/#{account.account_no}/#{today.strftime('%Y%m%d')}_#{account.account_no}.csv" }]
                  else        ['pending', {}]
                  end

  Download.create({
    account_id: account.id,
    bank_id:    account.bank_id,
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
  { key: 'max_retries',     value: '3',                          description: 'Maximum SFTP retry attempts per account per day' },
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
# API Calls — 30 days of fake request history
# ----------------------------------------------------------------
puts "\n→ API Calls"

API_ENDPOINTS = [
  { method: 'GET',   path: '/api/v1/accounts',              weight: 25 },
  { method: 'GET',   path: '/api/v1/accounts/:id',          weight: 20 },
  { method: 'GET',   path: '/api/v1/downloads',             weight: 20 },
  { method: 'GET',   path: '/api/v1/downloads/:id',         weight: 10 },
  { method: 'POST',  path: '/api/v1/downloads',             weight: 15 },
  { method: 'PATCH', path: '/api/v1/downloads/:id/status',  weight: 5  },
  { method: 'GET',   path: '/api/v1/status',                weight: 5  },
].freeze

CALLER_HOSTS = %w[10.0.1.10 10.0.1.11 10.0.1.20 10.0.2.5 192.168.1.100].freeze

API_ERRORS = {
  404 => 'Account not found',
  422 => 'account_id is required',
  409 => 'Download already exists for this account on this date',
}.freeze

def weighted_sample(entries)
  total  = entries.sum { |e| e[:weight] }
  target = rand(total)
  cum    = 0
  entries.each do |e|
    cum += e[:weight]
    return e if target < cum
  end
  entries.last
end

api_calls_seeded = 0

if ApiCall.count == 0
  accounts_ids = Account.select_map(:id)

  30.downto(1) do |days_ago|
    date      = Date.today - days_ago
    calls_per_day = 8 + rand(15)   # 8–22 calls per day

    calls_per_day.times do
      ep       = weighted_sample(API_ENDPOINTS)
      is_error = rand(100) < 8   # ~8% failure rate
      http_st  = if is_error
                   [404, 422, 409].sample
                 else
                   ep[:method] == 'POST' ? 201 : 200
                 end

      call_time   = Time.new(date.year, date.month, date.day,
                             8 + rand(12), rand(60), rand(60))
      duration_ms = 10 + rand(490)

      # Resolve :id placeholder to a real endpoint path
      resolved_path = if ep[:path].include?(':id') && accounts_ids.any?
                        ep[:path].sub(':id', accounts_ids.sample.to_s)
                      else
                        ep[:path]
                      end

      # Link to an account for single-resource endpoints
      account_id = if %w[/api/v1/accounts/:id /api/v1/downloads/:id /api/v1/downloads/:id/status].include?(ep[:path]) && accounts_ids.any?
                     accounts_ids.sample
                   elsif ep[:path] == '/api/v1/downloads' && ep[:method] == 'GET' && rand(2) == 0 && accounts_ids.any?
                     accounts_ids.sample
                   end

      ApiCall.create(
        http_method:   ep[:method],
        endpoint:      resolved_path,
        host:          CALLER_HOSTS.sample,
        account_id:    account_id,
        status:        http_st < 400 ? 'success' : 'failed',
        http_status:   http_st,
        duration_ms:   duration_ms,
        error_message: is_error ? API_ERRORS[http_st] : nil,
        created_at:    call_time
      )
      api_calls_seeded += 1
    end
  end

  puts "   #{api_calls_seeded} API call records inserted"
else
  puts "   #{ApiCall.count} API call records already present — skipping"
end

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
puts "\n── Seed complete ───────────────────────────────────────────────"
puts "   Banks:     #{Bank.count}"
puts "   Accounts:  #{Account.count}"
puts "   Downloads: #{Download.count} total"
puts "              #{Download.where(status: 'success').count} success"
puts "              #{Download.where(status: 'failed').count}  failed"
puts "              #{Download.where(status: 'running').count}  running"
puts "              #{Download.where(status: 'pending').count}  pending"
puts "   Settings:  #{Setting.count}"
puts "   API Calls: #{ApiCall.count}"
puts "────────────────────────────────────────────────────────────────"
