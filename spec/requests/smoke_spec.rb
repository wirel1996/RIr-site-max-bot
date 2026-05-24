# frozen_string_literal: true

require_relative '../../services/contacts_service'
require_relative '../../services/water_registry_service'

RSpec.describe 'Smoke API', type: :request do
  it 'health endpoint is reachable' do
    get '/api/health'
    expect(last_response.status).to eq(200)
    expect(last_response.body.to_s).not_to be_empty
  end

  it 'login and me flow works' do
    post_json '/api/auth/login', login: 'rspec_admin', password: 'Test1234#'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Set-Cookie']).to include('oke_session')

    get '/api/auth/me'
    expect(last_response.status).to eq(200)
    expect(json_body.dig('user', 'login')).to eq('rspec_admin')
  end

  it 'contact to object linkage is readable in object details' do
    login_as
    contact = Factories.create_gspo_contact(
      name: 'Smoke ГСПО',
      address: 'ул. Дымовая, 1',
      identifier: 'SMOKE-LINK-001'
    )

    get "/api/objects/gspo/#{contact['object_id']}"
    expect(last_response.status).to eq(200)
    expect(json_body.dig('object', 'identifier')).to eq('SMOKE-LINK-001')
    expect(json_body.fetch('contacts')).not_to be_empty
  end

  it 'disconnect switch event updates contact status and stores seals' do
    login_as
    contact = Factories.create_gspo_contact(
      name: 'Smoke Отключение',
      address: 'ул. Переключения, 2',
      identifier: 'SMOKE-SWITCH-001'
    )
    object_id = contact['object_id']
    Factories.create_water_row(object_id: object_id, identifier: 'SMOKE-SWITCH-001')

    post_json "/api/objects/gspo/#{object_id}/switch-events",
              kind: 'disconnect',
              event_date: '24.05.2026',
              place: 'ИТП, ТК Граница',
              seal_numbers: %w[1240001 1240002],
              actor_name: 'Smoke Author'
    expect(last_response.status).to eq(200)

    updated_contact = ContactsService.find(contact['id'])
    expect(updated_contact['disconnected']).to eq('да')
    expect(updated_contact['disconnected_date']).to eq('24.05.2026')

    get "/api/objects/gspo/#{object_id}"
    expect(last_response.status).to eq(200)
    event = json_body.fetch('switch_events').first
    expect(event['kind']).to eq('disconnect')
    expect(event['seal_numbers']).to include('1240001', '1240002')
  end

  it 'water row read and update flow works' do
    login_as
    contact = Factories.create_gspo_contact(
      name: 'Smoke Вода',
      address: 'ул. Водопроводная, 3',
      identifier: 'SMOKE-WATER-001'
    )
    water = Factories.create_water_row(
      object_id: contact['object_id'],
      identifier: 'SMOKE-WATER-001',
      gspo_name: 'Smoke Вода'
    )

    get "/api/metering/water/#{water['id']}"
    expect(last_response.status).to eq(200)
    expect(json_body['id']).to eq(water['id'])

    patch_json "/api/metering/water/#{water['id']}", payment: 'да'
    expect(last_response.status).to eq(200)
    row = WaterRegistryService.find(water['id'])
    expect(row[:payment].to_s).to eq('да')
  end
end
