# frozen_string_literal: true

RSpec.describe 'Contacts API', type: :request do
  before { login_as }

  describe 'PATCH /api/contacts/:id' do
    it 'updates allowed gspo fields' do
      contact = Factories.create_gspo_contact(identifier: 'API-GSPO-1')
      patch_json "/api/contacts/#{contact['id']}", phone: '79001230000', disconnected: 'да'
      expect(last_response.status).to eq(200)
      expect(json_body['phone']).to eq('79001230000')
    end

    it 'does not apply forbidden name on gspo contact' do
      contact = Factories.create_gspo_contact(name: 'Старое имя', identifier: 'API-GSPO-2')
      patch_json "/api/contacts/#{contact['id']}", name: 'Новое имя', phone: '79001110000'
      expect(last_response.status).to eq(200)
      expect(json_body['name']).to eq('Старое имя')
      expect(json_body['phone']).to eq('79001110000')
    end
  end
end
