require_relative '../db/database'

class Download < Sequel::Model(OctoBankX.db)
  many_to_one :account
  many_to_one :bank

  STATUSES = %w[pending running success failed].freeze

  plugin :validation_helpers

  def validate
    super
    validates_presence [:account_id, :bank_id, :date]
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

  def mark_running!
    update(status: 'running', started_at: Time.now)
  end

  def mark_success!(file_path)
    update(status: 'success', file_path: file_path, completed_at: Time.now)
  end

  def mark_failed!(message)
    update(status: 'failed', error_message: message, completed_at: Time.now)
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
