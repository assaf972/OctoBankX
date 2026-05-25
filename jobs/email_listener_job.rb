require 'net/imap'
require 'net/pop'
require 'mail'
require_relative '../models/email_sender'
require_relative '../models/download'
require_relative '../models/setting'

class EmailListenerJob
  def self.run
    protocol = Setting['email_protocol'] || 'imap'
    host     = Setting['email_host']
    port     = (Setting['email_port'] || (protocol == 'imap' ? '993' : '995')).to_i
    username = Setting['email_username']
    password = Setting['email_password']
    use_ssl  = Setting['email_ssl'] != 'false'

    return unless host && username && password

    approved_senders = EmailSender.where(active: true).all
    return if approved_senders.empty?

    approved_emails = approved_senders.map(&:sender_email).map(&:downcase)
    sender_bank_map = approved_senders.each_with_object({}) do |s, h|
      h[s.sender_email.downcase] = s.bank_id
    end

    case protocol.downcase
    when 'imap' then fetch_imap(host, port, username, password, use_ssl, approved_emails, sender_bank_map)
    when 'pop'  then fetch_pop(host, port, username, password, use_ssl, approved_emails, sender_bank_map)
    end
  end

  private

  def self.fetch_imap(host, port, username, password, use_ssl, approved_emails, sender_bank_map)
    download_dir = Setting['download_dir'] || '/var/octobankx/downloads'

    imap = Net::IMAP.new(host, port: port, ssl: use_ssl)
    imap.login(username, password)
    imap.select('INBOX')

    # Search for unseen messages
    message_ids = imap.search(['UNSEEN'])

    message_ids.each do |msg_id|
      envelope = imap.fetch(msg_id, 'ENVELOPE').first.attr['ENVELOPE']
      from_addr = envelope.from&.first
      next unless from_addr

      sender = "#{from_addr.mailbox}@#{from_addr.host}".downcase
      next unless approved_emails.include?(sender)

      bank_id = sender_bank_map[sender]
      next unless bank_id

      # Fetch the full message for attachment processing
      body = imap.fetch(msg_id, 'RFC822').first.attr['RFC822']
      mail = Mail.new(body)

      process_attachments(mail, bank_id, download_dir)

      # Mark as seen
      imap.store(msg_id, '+FLAGS', [:Seen])
    end
  ensure
    imap&.logout
    imap&.disconnect
  end

  def self.fetch_pop(host, port, username, password, use_ssl, approved_emails, sender_bank_map)
    download_dir = Setting['download_dir'] || '/var/octobankx/downloads'

    Net::POP3.enable_ssl if use_ssl
    Net::POP3.start(host, port, username, password) do |pop|
      pop.each_mail do |m|
        mail = Mail.new(m.pop)
        sender = mail.from&.first&.downcase
        next unless sender && approved_emails.include?(sender)

        bank_id = sender_bank_map[sender]
        next unless bank_id

        process_attachments(mail, bank_id, download_dir)
        m.delete
      end
    end
  end

  def self.process_attachments(mail, bank_id, download_dir)
    bank = Bank[bank_id]
    return unless bank

    bank_slug = bank.name.gsub(/\s+/, '_').downcase

    mail.attachments.each do |attachment|
      next unless attachment.filename =~ /\.(csv|xlsx?|txt|zip)$/i

      target_dir = File.join(download_dir, bank_slug)
      FileUtils.mkdir_p(target_dir)

      file_path = File.join(target_dir, attachment.filename)
      File.open(file_path, 'wb') { |f| f.write(attachment.decoded) }

      Download.create(
        bank_id:      bank_id,
        date:         Date.today,
        status:       'success',
        file_path:    file_path,
        started_at:   Time.now,
        completed_at: Time.now,
        created_at:   Time.now
      )
    end
  end
end
