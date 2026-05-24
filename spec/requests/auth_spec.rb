# frozen_string_literal: true

RSpec.describe 'Auth API', type: :request do
  describe 'GET /api/auth/me' do
    it 'returns 401 without session' do
      get '/api/auth/me'
      expect(last_response.status).to eq(401)
      expect(json_body['error'].to_s).not_to be_empty
    end

    it 'returns user after login' do
      login_as
      get '/api/auth/me'
      expect(last_response.status).to eq(200)
      expect(json_body['user']['login']).to eq('rspec_admin')
    end
  end

  describe 'POST /api/auth/login' do
    it 'returns 200 and sets session cookie' do
      post_json '/api/auth/login', login: 'rspec_admin', password: 'Test1234#'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Set-Cookie']).to include('oke_session')
    end
  end
end
