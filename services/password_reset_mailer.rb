# frozen_string_literal: true

require 'net/smtp'
require 'securerandom'
require 'time'

module PasswordResetMailer
  module_function

  def configured?
    !ENV['SMTP_HOST'].to_s.strip.empty? &&
      !ENV['SMTP_USERNAME'].to_s.strip.empty? &&
      !ENV['SMTP_PASSWORD'].to_s.strip.empty? &&
      !ENV['SMTP_FROM'].to_s.strip.empty?
  end

  def send_reset(email:, login:, reset_link:)
    raise 'SMTP not configured' unless configured?
    to = email.to_s.strip
    raise 'Email missing' if to.empty?

    host = ENV['SMTP_HOST'].to_s.strip
    port = (ENV['SMTP_PORT'] || '465').to_i
    user = ENV['SMTP_USERNAME'].to_s.strip
    pass = ENV['SMTP_PASSWORD'].to_s
    from = ENV['SMTP_FROM'].to_s.strip
    domain = from.split('@').last.to_s

    body = <<~MAIL
      From: #{from}
      To: #{to}
      Subject: Восстановление пароля
      MIME-Version: 1.0
      Content-Type: text/plain; charset=UTF-8
      Date: #{Time.now.rfc2822}
      Message-ID: <reset-#{SecureRandom.hex(8)}@#{domain}>

      Запрос на восстановление пароля для пользователя #{login}.
      Перейдите по ссылке и задайте новый пароль:
      #{reset_link}

      Ссылка действует 1 час.
      Если вы не запрашивали восстановление, просто проигнорируйте это письмо.
    MAIL

    smtp = Net::SMTP.new(host, port)
    smtp.enable_ssl if port == 465
    smtp.enable_starttls_auto if port != 465
    smtp.start('localhost', user, pass, :login) do |s|
      s.send_message(body, from, to)
    end
    true
  end
end
