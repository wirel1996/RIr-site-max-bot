#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby scripts/test_postbox_mail.rb [recipient@example.com]

require 'dotenv/load'
require_relative '../services/mail_delivery'

to = (ARGV[0] || ENV['POSTBOX_TEST_TO'] || ENV['SMTP_USERNAME']).to_s.strip
abort 'Usage: bundle exec ruby scripts/test_postbox_mail.rb recipient@example.com' if to.empty?
abort 'Mail not configured (MAIL_PROVIDER=postbox and POSTBOX_* in .env)' unless MailDelivery.configured?

puts "Provider: #{MailDelivery.provider}"
puts "From: #{MailDelivery.from_address}"
puts "To: #{to}"

MailDelivery.send_text(
  to: to,
  subject: 'Тест Postbox (max_bot)',
  text: "Проверка отправки через Yandex Cloud Postbox.\nВремя: #{Time.now}"
)
puts 'OK: message sent'
