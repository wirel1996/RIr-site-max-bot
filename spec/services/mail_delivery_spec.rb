# frozen_string_literal: true

require 'spec_helper'
require_relative '../../services/postbox_sigv4'

RSpec.describe PostboxSigV4 do
  it 'builds Authorization header for a POST body' do
    frozen = Time.utc(2024, 9, 20, 9, 16, 46)
    body = '{"FromEmailAddress":"a@b.c"}'
    headers = described_class.authorization_headers(
      access_key_id: 'AKID',
      secret_access_key: 'SECRET',
      method: 'POST',
      body: body,
      datetime: frozen
    )

    expect(headers['Authorization']).to start_with('AWS4-HMAC-SHA256 Credential=AKID/20240920/ru-central1/ses/aws4_request')
    expect(headers['Authorization']).to include('SignedHeaders=content-type;host;x-amz-date')
    expect(headers['X-Amz-Date']).to eq('20240920T091646Z')
  end
end
