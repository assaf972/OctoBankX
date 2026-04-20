require_relative '../db/database'

class ApiCall < Sequel::Model(OctoBankX.db)
  many_to_one :account   # nullable; account may not exist for every call

  STATUSES = %w[success failed].freeze
  METHODS  = %w[GET POST PATCH PUT DELETE].freeze

  plugin :validation_helpers

  def validate
    super
    validates_presence [:http_method, :endpoint, :status]
    validates_includes STATUSES, :status
  end

  def self.recent(limit = 100)
    order(Sequel.desc(:created_at)).limit(limit)
  end

  def self.distinct_endpoints
    order(:endpoint).select_map(:endpoint).uniq
  end

  def success? = status == 'success'
  def failed?  = status == 'failed'
end
