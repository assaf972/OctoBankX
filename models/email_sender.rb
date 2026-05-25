require_relative '../db/database'

class EmailSender < Sequel::Model(OctoBankX.db)
  many_to_one :bank

  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  def validate
    super
    validates_presence [:sender_name, :sender_email]
    validates_unique :sender_email
    validates_format(/\A[^@\s]+@[^@\s]+\z/, :sender_email, message: 'is not a valid email')
  end

  def active?
    active
  end

  dataset_module do
    def active
      where(active: true)
    end
  end
end
