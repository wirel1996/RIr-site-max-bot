# frozen_string_literal: true

require_relative 'mail_delivery'

module PasswordResetMailer
  module_function

  def configured?
    MailDelivery.configured?
  end

  def send_reset(email:, login:, reset_link:)
    text = <<~TEXT
      Запрос на восстановление пароля для пользователя #{login}.
      Перейдите по ссылке и задайте новый пароль:
      #{reset_link}

      Ссылка действует 1 час.
      Если вы не запрашивали восстановление, просто проигнорируйте это письмо.
    TEXT

    MailDelivery.send_text(
      to: email,
      subject: 'Восстановление пароля',
      text: text
    )
  end
end
