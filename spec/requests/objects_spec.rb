# frozen_string_literal: true

RSpec.describe 'Objects API', type: :request do
  before { login_as }

  let!(:contact) { Factories.create_gspo_contact(identifier: 'API-SW-1', address: 'ул. API, 1') }
  let(:registry_object_id) { contact['object_id'] }

  describe 'POST /api/objects/gspo/:id/switch-events' do
    before { Factories.create_water_row(object_id: registry_object_id) }

    it 'creates disconnect event' do
      post_json "/api/objects/gspo/#{registry_object_id}/switch-events",
                kind: 'disconnect',
                event_date: '21.05.2026',
                place: 'ввод',
                actor_name: 'RSpec Author'
      expect(last_response.status).to eq(200)
      expect(json_body['kind']).to eq('disconnect')
    end

    it 'creates connect event' do
      post_json "/api/objects/gspo/#{registry_object_id}/switch-events",
                kind: 'connect',
                event_date: '22.05.2026',
                actor_name: 'RSpec Author'
      expect(last_response.status).to eq(200)
      expect(json_body['kind']).to eq('connect')
    end
  end

  describe 'GET /api/objects/switch-act-authors' do
    it 'returns authors with position' do
      get '/api/objects/switch-act-authors'
      expect(last_response.status).to eq(200)
      logins = json_body['authors'].map { |a| a['login'] }
      expect(logins).to include('rspec_author')
    end
  end
end
