# frozen_string_literal: true

require 'net/smtp'
require 'securerandom'
require 'time'
require 'base64'

module BackupMailer
  module_function

  def configured?
    !ENV['SMTP_HOST'].to_s.strip.empty? &&
      !ENV['SMTP_USERNAME'].to_s.strip.empty? &&
      !ENV['SMTP_PASSWORD'].to_s.strip.empty? &&
      !ENV['SMTP_FROM'].to_s.strip.empty?
  end

  def send_backup(email:, subject:, text:, attachment_path: nil)
    raise 'SMTP not configured' unless configured?
    to = email.to_s.strip
    raise 'Email missing' if to.empty?

    host = ENV['SMTP_HOST'].to_s.strip
    port = (ENV['SMTP_PORT'] || '465').to_i
    user = ENV['SMTP_USERNAME'].to_s.strip
    pass = ENV['SMTP_PASSWORD'].to_s
    from = ENV['SMTP_FROM'].to_s.strip
    domain = from.split('@').last.to_s

    body =
      if attachment_path && File.file?(attachment_path)
        boundary = "----=_Backup_#{SecureRandom.hex(8)}"
        filename = File.basename(attachment_path)
        data = Base64.strict_encode64(File.binread(attachment_path))
        <<~MAIL
          From: #{from}
          To: #{to}
          Subject: #{subject}
          MIME-Version: 1.0
          Content-Type: multipart/mixed; boundary="#{boundary}"
          Date: #{Time.now.rfc2822}
          Message-ID: <backup-#{SecureRandom.hex(8)}@#{domain}>

          --#{boundary}
          Content-Type: text/plain; charset=UTF-8

          #{text}

          --#{boundary}
          Content-Type: application/zip; name="#{filename}"
          Content-Transfer-Encoding: base64
          Content-Disposition: attachment; filename="#{filename}"

          #{data}
          --#{boundary}--
        MAIL
      else
        <<~MAIL
          From: #{from}
          To: #{to}
          Subject: #{subject}
          MIME-Version: 1.0
          Content-Type: text/plain; charset=UTF-8
          Date: #{Time.now.rfc2822}
          Message-ID: <backup-#{SecureRandom.hex(8)}@#{domain}>

          #{text}
        MAIL
      end

    smtp = Net::SMTP.new(host, port)
    smtp.enable_ssl if port == 465
    smtp.enable_starttls_auto if port != 465
    smtp.start('localhost', user, pass, :login) do |s|
      s.send_message(body, from, to)
    end
    true
  end
end

