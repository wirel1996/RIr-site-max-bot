# frozen_string_literal: true

RSpec.describe 'Registry objects API', type: :request do
  before { login_as }

  let(:object_id) { Factories.build_registry_object(name: 'API объект', identifier: 'REG-API-1').to_i }

  describe 'PATCH /api/registry-objects/:id' do
    it 'updates registry object fields' do
      patch_json "/api/registry-objects/#{object_id}", name: 'Новое API имя'
      expect(last_response.status).to eq(200)
      expect(json_body['name']).to eq('Новое API имя')
    end
  end
end
