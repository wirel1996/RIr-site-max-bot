# frozen_string_literal: true

RSpec.describe 'Metering acts API', type: :request do
  before { login_as }

  let(:registry_object_id) { Factories.build_registry_object(identifier: 'ACT-OBJ').to_i }
  let!(:uute) { Factories.create_uute_gspo(object_id: registry_object_id) }

  describe 'POST /api/metering/gspo/:id/submit-act' do
    it 'submits input act' do
      post_json "/api/metering/gspo/#{uute[:id]}/submit-act",
                act_kind: 'input',
                date_input_uute: '2026-05-01',
                seal_calculator: 'П-100'
      expect(last_response.status).to eq(200)
      expect(json_body['act_number']).not_to be_empty
    end
  end
end
