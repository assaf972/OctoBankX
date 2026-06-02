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
    # Credentials are stored under EMAIL_USER / EMAIL_PWD (legacy keys still honoured).
    username = Setting['EMAIL_USER'] || Setting['email_username']
    password = Setting['EMAIL_PWD']  || Setting['email_password']
    use_ssl  = Setting['email_ssl'] != 'false'

    return unless host && username && password

    approved_senders = EmailSender.where(active: true).all
    # Safety: never touch the inbox until at least one approved sender exists,
    # otherwise every message would be treated as unapproved and deleted.
    return if approved_senders.empty?

    # Map of approved sender email (downcased) => bank_id.
    sender_bank_map = approved_senders.each_with_object({}) do |s, h|
      h[s.sender_email.downcase] = s.bank_id
    end

    case protocol.downcase
    when 'imap' then fetch_imap(host, port, username, password, use_ssl, sender_bank_map)
    when 'pop'  then fetch_pop(host, port, username, password, use_ssl, sender_bank_map)
    end
  end

  private

  def self.fetch_imap(host, port, username, password, use_ssl, sender_bank_map)
    download_dir = Setting['download_dir'] || '/var/octobankx/downloads'

    imap = Net::IMAP.new(host, port: port, ssl: use_ssl)
    imap.login(username, password)
    imap.select('INBOX')

    imap.search(['ALL']).each do |msg_id|
      envelope  = imap.fetch(msg_id, 'ENVELOPE').first.attr['ENVELOPE']
      from_addr = envelope.from&.first
      sender    = from_addr && "#{from_addr.mailbox}@#{from_addr.host}".downcase
      bank_id   = sender && sender_bank_map[sender]

      if bank_id
        # Approved sender: download attachments and mark the message as read.
        body = imap.fetch(msg_id, 'RFC822').first.attr['RFC822']
        process_attachments(Mail.new(body), bank_id, download_dir)
        imap.store(msg_id, '+FLAGS', [:Seen])
      else
        # Not from an approved sender: delete the message.
        imap.store(msg_id, '+FLAGS', [:Deleted])
      end
    end

    imap.expunge
  ensure
    imap&.logout
    imap&.disconnect
  end

  def self.fetch_pop(host, port, username, password, use_ssl, sender_bank_map)
    download_dir = Setting['download_dir'] || '/var/octobankx/downloads'

    Net::POP3.enable_ssl if use_ssl
    Net::POP3.start(host, port, username, password) do |pop|
      pop.each_mail do |m|
        mail    = Mail.new(m.pop)
        sender  = mail.from&.first&.downcase
        bank_id = sender && sender_bank_map[sender]

        if bank_id
          # Approved sender: download attachments, then remove the message.
          process_attachments(mail, bank_id, download_dir)
        end

        # Whether approved (processed) or not, the message is removed from the box.
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

      # Never download/process the same file twice.
      next if Download.where(file_path: file_path).count.positive?

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
