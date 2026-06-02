require_relative '../db/database'

class LogEvent < Sequel::Model(OctoBankX.db)
  many_to_one :download

  KINDS = %w[log error exception notification].freeze

  plugin :validation_helpers

  def validate
    super
    validates_presence [:kind, :message]
    validates_includes KINDS, :kind
  end

  # --- Convenience recorders ----------------------------------------

  def self.log(message, download: nil)
    record('log', message, download: download)
  end

  def self.error(message, download: nil)
    record('error', message, download: download)
  end

  def self.notification(message, download: nil)
    record('notification', message, download: download)
  end

  # Records an exception event capturing the class, message and full
  # backtrace (following the exception's cause chain).
  def self.exception(error, message: nil, download: nil)
    create(
      kind:        'exception',
      message:     message || "#{error.class}: #{error.message}",
      error_class: error.class.name,
      backtrace:   format_backtrace(error),
      download_id: download&.id,
      created_at:  Time.now
    )
  end

  def self.record(kind, message, download: nil)
    create(kind: kind, message: message, download_id: download&.id, created_at: Time.now)
  end

  def self.format_backtrace(error)
    lines   = []
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
end
