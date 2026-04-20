require_relative '../db/database'

class Account < Sequel::Model(OctoBankX.db)
  many_to_one :bank
  one_to_many :downloads

  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  def validate
    super
    validates_presence [:name, :account_no, :bank_id]
    validates_unique :account_no
  end
end
