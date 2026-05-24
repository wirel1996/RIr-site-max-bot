# frozen_string_literal: true

RSpec.describe 'Water metering API', type: :request do
  before { login_as }

  let(:registry_object_id) { Factories.build_registry_object(identifier: 'W-API-1').to_i }
  let!(:row) { Factories.create_water_row(object_id: registry_object_id, payment: 'да', payment_date: '2026-05-01') }

  describe 'GET /api/metering/water/:id' do
    it 'returns water row' do
      get "/api/metering/water/#{row['id']}"
      expect(last_response.status).to eq(200)
      expect(json_body['id']).to eq(row['id'])
    end
  end

  describe 'PATCH /api/metering/water/:id' do
    it 'updates editable field' do
      patch_json "/api/metering/water/#{row['id']}", note: 'API note'
      expect(last_response.status).to eq(200)
      expect(json_body['note']).to eq('API note')
    end
  end

  describe 'GET /api/metering/water/phoneogram/history' do
    it 'returns last export info' do
      WaterPhoneogramService.record_export!(
        payment_from: '2026-04-01',
        payment_to: '2026-05-01',
        phoneogram_number: '42',
        document_date: '2026-05-21'
      )
      get '/api/metering/water/phoneogram/history'
      expect(last_response.status).to eq(200)
      expect(json_body['last_export']['phoneogram_number']).to eq('42')
    end
  end

end
