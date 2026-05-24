# frozen_string_literal: true

require_relative 'mail_delivery'

module BackupMailer
  module_function

  def configured?
    MailDelivery.configured?
  end

  def send_backup(email:, subject:, text:, attachment_path: nil)
    if attachment_path && File.file?(attachment_path)
      MailDelivery.send_with_attachment(
        to: email,
        subject: subject,
        text: text,
        attachment_path: attachment_path
      )
    else
      MailDelivery.send_text(to: email, subject: subject, text: text)
    end
  end
end
