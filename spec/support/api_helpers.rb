# frozen_string_literal: true

module ApiHelpers
  def app
    ContactsWeb
  end

  def json_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  def login_as(login = 'rspec_admin', password = 'Test1234#')
    post '/api/auth/login', { login: login, password: password }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(200), "login failed: #{last_response.body}"
  end

  def auth_headers
    {}
  end

  def patch_json(path, body)
    patch path, body.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  def post_json(path, body = {})
    post path, body.to_json, 'CONTENT_TYPE' => 'application/json'
  end
end
