require_relative '../db/database'

class Download < Sequel::Model(OctoBankX.db)
  many_to_one :bank
  one_to_many :log_events

  STATUSES = %w[pending running success failed].freeze

  plugin :validation_helpers

  def validate
    super
    validates_presence [:bank_id, :date]
    validates_includes STATUSES, :status
  end

  def self.for_date(date = Date.today)
    where(date: date)
  end

  def self.recent(limit = 10)
    order(Sequel.desc(:created_at)).limit(limit)
  end

  def pending?  = status == 'pending'
  def running?  = status == 'running'
  def success?  = status == 'success'
  def failed?   = status == 'failed'

  # Human-friendly job name, e.g. "Bank Leumi — 2026-05-25"
  def display_name
    "#{bank&.name} — #{date}"
  end

  # A finished job (success/failed) can be re-run; an active one can be killed.
  def rerunnable? = success? || failed?
  def killable?   = pending? || running?

  def mark_running!
    update(status: 'running', started_at: Time.now)
  end

  def mark_success!(file_path)
    update(status: 'success', file_path: file_path, completed_at: Time.now)
  end

  def mark_failed!(message, backtrace: nil)
    attrs = { status: 'failed', error_message: message, completed_at: Time.now }
    attrs[:backtrace] = backtrace unless backtrace.nil?
    update(attrs)
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
