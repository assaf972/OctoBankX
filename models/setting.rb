require_relative '../db/database'

class Setting < Sequel::Model(OctoBankX.db)
  plugin :validation_helpers

  def validate
    super
    validates_presence :key
    validates_unique :key
  end

  def self.[](key)
    find(key: key.to_s)&.value
  end

  def self.set(key, value, description: nil)
    existing = find(key: key.to_s)
    if existing
      existing.update(value: value.to_s, updated_at: Time.now)
    else
      create(key: key.to_s, value: value.to_s, description: description, updated_at: Time.now)
    end
  end

  def self.all_as_hash
    all.each_with_object({}) { |s, h| h[s.key] = s.value }
  end
end
