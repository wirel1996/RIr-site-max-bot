# frozen_string_literal: true

require_relative '../../services/uute_service'
require_relative '../../services/audit_log_service'

RSpec.describe 'Delete permissions', type: :request do
  describe 'non-admin (full role)' do
    before { login_as('rspec_author') }

    let!(:contact) { Factories.create_phys_contact(name: 'Delete perm test') }
    let(:contact_id) { contact['id'] }

    it 'returns 403 on DELETE /api/contacts/:id' do
      delete "/api/contacts/#{contact_id}"
      expect(last_response.status).to eq(403)
      expect(json_body['error']).to include('admin')
    end

    it 'returns 403 on DELETE /api/metering/links' do
      gspo = Factories.create_gspo_contact(identifier: 'DEL-LINK')
      uute = Factories.create_uute_gspo(object_id: gspo['object_id'])
      UuteService.create_link(contact_id: gspo['id'], uute_id: uute[:id])

      delete '/api/metering/links',
             { contact_id: gspo['id'], uute_id: uute[:id] }.to_json,
             'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(403)
    end

    it 'returns 403 on POST delete-act' do
      object_id = Factories.build_registry_object(identifier: 'DEL-ACT').to_i
      uute = Factories.create_uute_gspo(object_id: object_id)
      uute_id = uute[:id]
      before = UuteService.find(uute_id)
      result = UuteService.submit_act(
        uute_id,
        'act_kind' => 'input',
        'date_input_uute' => '2026-05-01',
        'seal_calculator' => 'П-1'
      )
      AuditLogService.record_changes(
        actor: { login: 'rspec_author', name: 'RSpec Author' },
        action: UuteService.act_submit_audit_action('input'),
        entity_type: 'metering',
        entity_id: uute_id.to_s,
        entity_label: 'uute',
        before: before,
        after: result[:record],
        fields: result[:fields].map(&:to_s)
      )

      post_json "/api/metering/gspo/#{uute_id}/delete-act", act_kind: 'input'
      expect(last_response.status).to eq(403)
    end

    it 'returns 403 on DELETE /api/metering/:category/:id' do
      object_id = Factories.build_registry_object(identifier: 'DEL-UUTE').to_i
      uute = Factories.create_uute_gspo(object_id: object_id)
      delete "/api/metering/gspo/#{uute[:id]}"
      expect(last_response.status).to eq(403)
    end

    it 'returns 403 on DELETE /api/contacts/categories/:key' do
      delete '/api/contacts/categories/test_cat'
      expect(last_response.status).to eq(403)
    end
  end

  describe 'admin' do
    before { login_as('rspec_admin') }

    it 'can delete a contact' do
      contact = Factories.create_phys_contact(name: 'Admin delete test')
      delete "/api/contacts/#{contact['id']}"
      expect(last_response.status).to eq(200)
      expect(json_body['ok']).to be true
    end

    it 'can delete a metering record' do
      object_id = Factories.build_registry_object(identifier: 'ADMIN-DEL-UUTE').to_i
      uute = Factories.create_uute_gspo(object_id: object_id)
      delete "/api/metering/gspo/#{uute[:id]}"
      expect(last_response.status).to eq(200)
      expect(json_body['ok']).to be true
      expect(UuteService.find(uute[:id])).to be_nil
    end
  end
end
