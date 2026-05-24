# frozen_string_literal: true

RSpec.describe 'Metering categories API', type: :request do
  before { login_as }

  describe 'GET /api/metering/overview' do
    it 'returns categories with counts' do
      object_id = Factories.build_registry_object(identifier: 'OV-UUTE').to_i
      Factories.create_uute_gspo(object_id: object_id)

      get '/api/metering/overview'
      expect(last_response.status).to eq(200)
      gspo = json_body['categories'].find { |c| c['key'] == 'gspo' }
      expect(gspo).not_to be_nil
      expect(gspo['label']).to eq('ГСПО')
      expect(gspo['system']).to be true
      expect(gspo['count']).to be >= 1
    end
  end

  describe 'POST /api/metering/categories' do
    it 'creates a custom category' do
      post_json '/api/metering/categories', label: 'Складские', key: 'warehouse_test'
      expect(last_response.status).to eq(201)
      expect(json_body['key']).to eq('warehouse_test')
      expect(json_body['label']).to eq('Складские')
    end

    it 'rejects duplicate key' do
      post_json '/api/metering/categories', label: 'Дубликат', key: 'dup_cat'
      expect(last_response.status).to eq(201)

      post_json '/api/metering/categories', label: 'Ещё раз', key: 'dup_cat'
      expect(last_response.status).to eq(400)
    end
  end

  describe 'PATCH /api/metering/categories/:key' do
    it 'updates label and sort order' do
      post_json '/api/metering/categories', label: 'Старая', key: 'patch_cat'

      patch_json '/api/metering/categories/patch_cat', label: 'Новая', sort_order: 99
      expect(last_response.status).to eq(200)
      expect(json_body['label']).to eq('Новая')
      expect(json_body['sort_order']).to eq(99)
    end
  end

  describe 'DELETE /api/metering/categories/:key' do
    it 'returns 403 for non-admin' do
      login_as('rspec_author')
      post_json '/api/metering/categories', label: 'Удалить', key: 'del_cat_full'
      expect(last_response.status).to eq(201)

      delete '/api/metering/categories/del_cat_full'
      expect(last_response.status).to eq(403)
    end

    it 'deletes empty non-system category for admin' do
      login_as('rspec_admin')
      post_json '/api/metering/categories', label: 'Пустая', key: 'empty_cat'

      delete '/api/metering/categories/empty_cat'
      expect(last_response.status).to eq(200)
      expect(json_body['ok']).to be true
    end

    it 'rejects delete when category has records' do
      login_as('rspec_admin')
      post_json '/api/metering/categories', label: 'С данными', key: 'with_data'
      object_id = Factories.build_registry_object(identifier: 'CAT-HAS-UUTE').to_i
      post_json '/api/metering/with_data', object_id: object_id
      expect(last_response.status).to eq(201)

      delete '/api/metering/categories/with_data'
      expect(last_response.status).to eq(400)
    end

    it 'rejects delete of system category' do
      login_as('rspec_admin')
      delete '/api/metering/categories/gspo'
      expect(last_response.status).to eq(400)
    end
  end

  describe 'POST /api/metering/:category' do
    it 'creates uute in known category' do
      object_id = Factories.build_registry_object(identifier: 'CREATE-UUTE').to_i

      post_json '/api/metering/gspo', object_id: object_id, calculator_type: 'ВКТ-7'
      expect(last_response.status).to eq(201)
      expect(json_body['id']).to be > 0
      expect(json_body['calculator_type']).to eq('ВКТ-7')
    end

    it 'rejects unknown category' do
      object_id = Factories.build_registry_object(identifier: 'BAD-CAT').to_i

      post_json '/api/metering/no_such_category', object_id: object_id
      expect(last_response.status).to eq(400)
    end
  end

  describe 'DELETE /api/metering/:category/:id' do
    it 'removes record and contact links for admin' do
      login_as('rspec_admin')
      contact = Factories.create_gspo_contact(identifier: 'DEL-UUTE-LINK')
      uute = Factories.create_uute_gspo(object_id: contact['object_id'])
      UuteService.create_link(contact_id: contact['id'], uute_id: uute[:id])

      delete "/api/metering/gspo/#{uute[:id]}"
      expect(last_response.status).to eq(200)
      expect(json_body['ok']).to be true
      expect(UuteService.find(uute[:id])).to be_nil

      links = UuteDB.with_db { |db| UuteDB.links_for_uute(db, uute[:id]) }
      expect(links).to be_empty
    end

    it 'returns 400 when category in URL does not match record' do
      login_as('rspec_admin')
      object_id = Factories.build_registry_object(identifier: 'WRONG-CAT-URL').to_i
      uute = Factories.create_uute_gspo(object_id: object_id)

      delete "/api/metering/phys/#{uute[:id]}"
      expect(last_response.status).to eq(400)
    end
  end
end
