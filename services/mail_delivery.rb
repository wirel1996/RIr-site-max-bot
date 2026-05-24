# frozen_string_literal: true

require 'json'
require 'net/http'
require 'net/smtp'
require 'base64'
require 'securerandom'
require 'time'
require 'uri'
require_relative 'postbox_sigv4'

module MailDelivery
  class Error < StandardError; end

  module_function

  def provider
    (ENV['MAIL_PROVIDER'] || 'smtp').to_s.strip.downcase
  end

  def configured?
    postbox? ? postbox_configured? : smtp_configured?
  end

  def from_address
    if postbox?
      ENV['POSTBOX_FROM'].to_s.strip
    else
      ENV['SMTP_FROM'].to_s.strip
    end
  end

  def send_text(to:, subject:, text:)
    to = to.to_s.strip
    raise Error, 'Email missing' if to.empty?
    raise Error, 'Mail not configured' unless configured?

    if postbox?
      postbox_send_simple(to: to, subject: subject, text: text)
    else
      smtp_send_message(build_text_mime(to: to, subject: subject, text: text))
    end
    true
  end

  def send_with_attachment(to:, subject:, text:, attachment_path:)
    to = to.to_s.strip
    raise Error, 'Email missing' if to.empty?
    raise Error, 'Mail not configured' unless configured?

    if postbox?
      postbox_send_raw(to: to, subject: subject, text: text, attachment_path: attachment_path)
    else
      smtp_send_message(build_attachment_mime(to: to, subject: subject, text: text, attachment_path: attachment_path))
    end
    true
  end

  def postbox?
    provider == 'postbox'
  end

  def postbox_configured?
    !ENV['POSTBOX_ACCESS_KEY_ID'].to_s.strip.empty? &&
      !ENV['POSTBOX_SECRET_ACCESS_KEY'].to_s.strip.empty? &&
      !ENV['POSTBOX_FROM'].to_s.strip.empty?
  end

  def smtp_configured?
    !ENV['SMTP_HOST'].to_s.strip.empty? &&
      !ENV['SMTP_USERNAME'].to_s.strip.empty? &&
      !ENV['SMTP_PASSWORD'].to_s.strip.empty? &&
      !ENV['SMTP_FROM'].to_s.strip.empty?
  end

  def postbox_send_simple(to:, subject:, text:)
    body = {
      FromEmailAddress: from_address,
      Destination: { ToAddresses: [to] },
      Content: {
        Simple: {
          Subject: { Data: subject, Charset: 'UTF-8' },
          Body: {
            Text: { Data: text, Charset: 'UTF-8' }
          }
        }
      }
    }
    configuration = ENV['POSTBOX_CONFIGURATION_SET'].to_s.strip
    body[:ConfigurationSetName] = configuration unless configuration.empty?

    postbox_request(body)
  end

  def postbox_send_raw(to:, subject:, text:, attachment_path:)
    raw_mime = build_attachment_mime(to: to, subject: subject, text: text, attachment_path: attachment_path)
    payload = {
      FromEmailAddress: from_address,
      Destination: { ToAddresses: [to] },
      Content: {
        Raw: {
          Data: Base64.strict_encode64(raw_mime)
        }
      }
    }
    configuration = ENV['POSTBOX_CONFIGURATION_SET'].to_s.strip
    payload[:ConfigurationSetName] = configuration unless configuration.empty?

    postbox_request(payload)
  end

  def postbox_request(payload_hash)
    json = JSON.generate(payload_hash)
    headers = PostboxSigV4.authorization_headers(
      access_key_id: ENV['POSTBOX_ACCESS_KEY_ID'].to_s.strip,
      secret_access_key: ENV['POSTBOX_SECRET_ACCESS_KEY'].to_s.strip,
      method: 'POST',
      body: json
    )

    uri = URI("https://#{PostboxSigV4::HOST}#{PostboxSigV4::PATH}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |k, v| request[k] = v }
    request.body = json

    response = http.request(request)
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    detail = response.body.to_s.strip
    detail = detail[0, 500] unless detail.empty?
    raise Error, "Postbox HTTP #{response.code}#{detail.empty? ? '' : ": #{detail}"}"
  rescue JSON::ParserError
    raise Error, "Postbox HTTP #{response.code}" if response

    raise
  end

  def smtp_send_message(mime_body)
    from = from_address
    to = mime_body[/^To:\s*(.+)$/i, 1].to_s.strip
    host = ENV['SMTP_HOST'].to_s.strip
    port = (ENV['SMTP_PORT'] || '465').to_i
    user = ENV['SMTP_USERNAME'].to_s.strip
    pass = ENV['SMTP_PASSWORD'].to_s

    smtp = Net::SMTP.new(host, port)
    smtp.enable_ssl if port == 465
    smtp.enable_starttls_auto if port != 465
    smtp.start('localhost', user, pass, :login) do |s|
      s.send_message(mime_body, from, to)
    end
  end

  def build_text_mime(to:, subject:, text:)
    from = from_address
    domain = from.split('@').last.to_s
    <<~MAIL
      From: #{from}
      To: #{to}
      Subject: #{subject}
      MIME-Version: 1.0
      Content-Type: text/plain; charset=UTF-8
      Date: #{Time.now.rfc2822}
      Message-ID: <mail-#{SecureRandom.hex(8)}@#{domain}>

      #{text}
    MAIL
  end

  def build_attachment_mime(to:, subject:, text:, attachment_path:)
    from = from_address
    domain = from.split('@').last.to_s

    unless attachment_path && File.file?(attachment_path)
      return build_text_mime(to: to, subject: subject, text: text)
    end

    boundary = "----=_Mail_#{SecureRandom.hex(8)}"
    filename = File.basename(attachment_path)
    data = Base64.strict_encode64(File.binread(attachment_path))
    wrapped = data.scan(/.{1,76}/).join("\n")

    <<~MAIL
      From: #{from}
      To: #{to}
      Subject: #{subject}
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="#{boundary}"
      Date: #{Time.now.rfc2822}
      Message-ID: <mail-#{SecureRandom.hex(8)}@#{domain}>

      --#{boundary}
      Content-Type: text/plain; charset=UTF-8

      #{text}

      --#{boundary}
      Content-Type: application/zip; name="#{filename}"
      Content-Transfer-Encoding: base64
      Content-Disposition: attachment; filename="#{filename}"

      #{wrapped}
      --#{boundary}--
    MAIL
  end
  private_class_method :postbox_send_simple, :postbox_send_raw, :postbox_request, :smtp_send_message,
                       :build_text_mime, :build_attachment_mime
end
