require_relative '../spec_helper'

RSpec.describe EmailSender do
  let(:bank) { create(:bank) }

  # ----------------------------------------------------------------
  # Validations
  # ----------------------------------------------------------------
  describe 'validations' do
    it 'is valid with all required attributes' do
      es = build(:email_sender, bank: bank)
      expect(es.valid?).to be true
    end

    it 'requires sender_name' do
      es = build(:email_sender, sender_name: nil, bank: bank)
      expect(es.valid?).to be false
      expect(es.errors[:sender_name]).not_to be_empty
    end

    it 'requires sender_email' do
      es = build(:email_sender, sender_email: nil, bank: bank)
      expect(es.valid?).to be false
      expect(es.errors[:sender_email]).not_to be_empty
    end

    it 'rejects duplicate sender_email' do
      create(:email_sender, sender_email: 'dup@bank.test', bank: bank)
      es = build(:email_sender, sender_email: 'dup@bank.test', bank: bank)
      expect(es.valid?).to be false
      expect(es.errors[:sender_email]).not_to be_empty
    end

    it 'rejects invalid email format (no @)' do
      es = build(:email_sender, sender_email: 'not-an-email', bank: bank)
      expect(es.valid?).to be false
      expect(es.errors[:sender_email]).not_to be_empty
    end

    it 'rejects email with spaces' do
      es = build(:email_sender, sender_email: 'bad email@bank.test', bank: bank)
      expect(es.valid?).to be false
    end

    it 'accepts valid email formats' do
      %w[user@bank.co.il info+tag@bank.test a@b.io].each do |email|
        es = build(:email_sender, sender_email: email, bank: bank)
        expect(es.valid?).to be(true), "Expected #{email} to be valid"
      end
    end
  end

  # ----------------------------------------------------------------
  # Associations
  # ----------------------------------------------------------------
  describe 'associations' do
    it 'belongs to a bank' do
      es = create(:email_sender, bank: bank)
      expect(es.bank).to eq bank
    end

    it 'can exist without a bank (bank_id nil)' do
      es = build(:email_sender, bank_id: nil)
      expect(es.valid?).to be true
    end
  end

  # ----------------------------------------------------------------
  # #active?
  # ----------------------------------------------------------------
  describe '#active?' do
    it 'returns true when active is true' do
      es = create(:email_sender, active: true, bank: bank)
      expect(es.active?).to be true
    end

    it 'returns false when active is false' do
      es = create(:email_sender, active: false, bank: bank)
      expect(es.active?).to be false
    end
  end

  # ----------------------------------------------------------------
  # Dataset .active scope
  # ----------------------------------------------------------------
  describe '.active scope' do
    it 'returns only active senders' do
      create(:email_sender, bank: bank, active: true,  sender_email: 'a@test.com')
      create(:email_sender, bank: bank, active: false, sender_email: 'b@test.com')
      create(:email_sender, bank: bank, active: true,  sender_email: 'c@test.com')

      results = EmailSender.active.all
      expect(results.size).to eq 2
      expect(results.map(&:sender_email)).to contain_exactly('a@test.com', 'c@test.com')
    end

    it 'returns empty when none active' do
      create(:email_sender, bank: bank, active: false, sender_email: 'd@test.com')
      expect(EmailSender.active.count).to eq 0
    end
  end

  # ----------------------------------------------------------------
  # Timestamps plugin
  # ----------------------------------------------------------------
  describe 'timestamps' do
    it 'sets created_at and updated_at on create' do
      es = EmailSender.create(
        sender_name: 'Test', sender_email: 'ts@bank.test',
        bank_id: bank.id, active: true
      )
      expect(es.created_at).not_to be_nil
      expect(es.updated_at).not_to be_nil
    end
  end
end
