# frozen_string_literal: true

require 'openssl'
require 'digest'

# AWS Signature Version 4 for Yandex Cloud Postbox (SES-compatible API).
module PostboxSigV4
  REGION = 'ru-central1'
  SERVICE = 'ses'
  HOST = (ENV['POSTBOX_HOST'] || 'postbox.cloud.yandex.net').to_s.strip
  PATH = '/v2/email/outbound-emails'

  module_function

  def authorization_headers(access_key_id:, secret_access_key:, method:, body:, datetime: Time.now.utc)
    amz_date = datetime.utc.strftime('%Y%m%dT%H%M%SZ')
    date_stamp = datetime.utc.strftime('%Y%m%d')
    payload_hash = Digest::SHA256.hexdigest(body)

    canonical_headers = [
      'content-type:application/json',
      "host:#{HOST}",
      "x-amz-date:#{amz_date}"
    ].join("\n") + "\n"

    signed_headers = 'content-type;host;x-amz-date'
    canonical_request = [
      method.upcase,
      PATH,
      '',
      canonical_headers,
      signed_headers,
      payload_hash
    ].join("\n")

    credential_scope = "#{date_stamp}/#{REGION}/#{SERVICE}/aws4_request"
    string_to_sign = [
      'AWS4-HMAC-SHA256',
      amz_date,
      credential_scope,
      Digest::SHA256.hexdigest(canonical_request)
    ].join("\n")

    signing_key = derive_signing_key(secret_access_key, date_stamp)
    signature = OpenSSL::HMAC.hexdigest('SHA256', signing_key, string_to_sign)
    credential = "#{access_key_id}/#{credential_scope}"

    {
      'Authorization' => "AWS4-HMAC-SHA256 Credential=#{credential}, SignedHeaders=#{signed_headers}, Signature=#{signature}",
      'X-Amz-Date' => amz_date,
      'Content-Type' => 'application/json',
      'Host' => HOST
    }
  end

  def derive_signing_key(secret_access_key, date_stamp)
    key = hmac_bytes("AWS4#{secret_access_key}", date_stamp)
    key = hmac_bytes(key, REGION)
    key = hmac_bytes(key, SERVICE)
    hmac_bytes(key, 'aws4_request')
  end

  def hmac_bytes(key, data)
    key = key.dup.force_encoding(Encoding::BINARY) if key.is_a?(String)
    OpenSSL::HMAC.digest('SHA256', key, data)
  end
  private_class_method :derive_signing_key, :hmac_bytes
end
