require_relative '../spec_helper'

RSpec.describe 'Email Senders Routes' do
  let(:app)  { OctoBankXApp }
  let(:bank) { create(:bank) }

  # ----------------------------------------------------------------
  # Desktop routes
  # ----------------------------------------------------------------
  describe 'GET /email_senders' do
    it 'returns 200' do
      get '/email_senders'
      expect(last_response.status).to eq 200
    end

    it 'lists existing email senders' do
      create(:email_sender, sender_name: 'Leumi Bot', sender_email: 'bot@leumi.co.il', bank: bank)
      get '/email_senders'
      expect(last_response.body).to include('Leumi Bot')
      expect(last_response.body).to include('bot@leumi.co.il')
    end

    it 'shows the add-sender form' do
      get '/email_senders'
      expect(last_response.body).to include('sender_name')
      expect(last_response.body).to include('sender_email')
    end
  end

  describe 'POST /email_senders' do
    it 'creates a new email sender and redirects' do
      expect {
        post '/email_senders', sender_name: 'New Sender', sender_email: 'new@bank.test', bank_id: bank.id
      }.to change(EmailSender, :count).by(1)

      expect(last_response).to be_redirect
      follow_redirect!
      expect(last_response.body).to include('New Sender')
    end

    it 'sets the sender as active by default' do
      post '/email_senders', sender_name: 'Active', sender_email: 'active@bank.test', bank_id: bank.id
      es = EmailSender.last
      expect(es.active).to be true
    end

    it 'handles missing bank_id gracefully' do
      post '/email_senders', sender_name: 'No Bank', sender_email: 'nobank@test.com', bank_id: ''
      es = EmailSender.last
      expect(es.bank_id).to be_nil
    end

    it 'rejects invalid email and redirects with error' do
      expect {
        post '/email_senders', sender_name: 'Bad', sender_email: 'not-email', bank_id: bank.id
      }.not_to change(EmailSender, :count)

      expect(last_response).to be_redirect
    end

    it 'rejects duplicate email addresses' do
      create(:email_sender, sender_email: 'dup@bank.test', bank: bank)

      expect {
        post '/email_senders', sender_name: 'Dup', sender_email: 'dup@bank.test', bank_id: bank.id
      }.not_to change(EmailSender, :count)

      expect(last_response).to be_redirect
    end
  end

  describe 'POST /email_senders/:id/toggle' do
    it 'toggles active from true to false' do
      es = create(:email_sender, active: true, bank: bank)
      post "/email_senders/#{es.id}/toggle"

      expect(last_response).to be_redirect
      es.reload
      expect(es.active).to be false
    end

    it 'toggles active from false to true' do
      es = create(:email_sender, active: false, bank: bank)
      post "/email_senders/#{es.id}/toggle"

      es.reload
      expect(es.active).to be true
    end

    it 'redirects even for non-existent id' do
      post '/email_senders/9999/toggle'
      expect(last_response).to be_redirect
    end
  end

  describe 'POST /email_senders/:id/delete' do
    it 'deletes the email sender' do
      es = create(:email_sender, bank: bank)
      expect {
        post "/email_senders/#{es.id}/delete"
      }.to change(EmailSender, :count).by(-1)

      expect(last_response).to be_redirect
    end

    it 'redirects even for non-existent id' do
      post '/email_senders/9999/delete'
      expect(last_response).to be_redirect
    end
  end

  # ----------------------------------------------------------------
  # Mobile routes
  # ----------------------------------------------------------------
  describe 'GET /mobile/email_senders' do
    it 'returns 200' do
      get '/mobile/email_senders'
      expect(last_response.status).to eq 200
    end

    it 'lists email senders in mobile layout' do
      create(:email_sender, sender_name: 'Mobile Test', sender_email: 'mobile@test.com', bank: bank)
      get '/mobile/email_senders'
      expect(last_response.body).to include('Mobile Test')
    end
  end

  describe 'POST /mobile/email_senders' do
    it 'creates a sender and redirects to mobile page' do
      expect {
        post '/mobile/email_senders', sender_name: 'Mobile New', sender_email: 'mnew@bank.test', bank_id: bank.id
      }.to change(EmailSender, :count).by(1)

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/mobile/email_senders')
    end

    it 'rejects invalid data and redirects' do
      expect {
        post '/mobile/email_senders', sender_name: '', sender_email: 'x@y.com'
      }.not_to change(EmailSender, :count)

      expect(last_response).to be_redirect
    end
  end

  describe 'POST /mobile/email_senders/:id/toggle' do
    it 'toggles active status' do
      es = create(:email_sender, active: true, bank: bank)
      post "/mobile/email_senders/#{es.id}/toggle"

      es.reload
      expect(es.active).to be false
      expect(last_response).to be_redirect
    end
  end

  describe 'POST /mobile/email_senders/:id/delete' do
    it 'deletes the sender' do
      es = create(:email_sender, bank: bank)
      expect {
        post "/mobile/email_senders/#{es.id}/delete"
      }.to change(EmailSender, :count).by(-1)
    end
  end
end
