# frozen_string_literal: true

require_relative '../../storage/uute_db'
require_relative '../../services/objects_service'
require_relative '../../services/uute_service'
require_relative '../../services/contacts_service'
require_relative '../../services/water_registry_service'

RSpec.describe 'Cross-table flows' do
  it 'syncs registry object, contact, water, switch events and uute link' do
    contact = Factories.create_gspo_contact(
      name: 'Сквозной объект',
      address: 'ул. Сквозная, 1',
      identifier: 'FLOW-001'
    )
    object_id = contact['object_id']
    water = Factories.create_water_row(object_id: object_id, identifier: 'FLOW-001')

    disconnect = ObjectsService.create_switch_event(
      object_id,
      'kind' => 'disconnect',
      'event_date' => '15.05.2026',
      'place' => 'шкаф',
      'actor_name' => 'Контролер'
    )

    contact_after = ContactsService.find(contact['id'])
    expect(contact_after['disconnected']).to eq('да')

    water_after = WaterRegistryService.find(water['id'])
    expect(water_after[:third_party_disconnection_note]).to include(disconnect[:act_number])
    expect(water_after[:third_party_disconnection].to_s.strip).to be_empty

    connect = ObjectsService.create_switch_event(
      object_id,
      'kind' => 'connect',
      'event_date' => '20.05.2026',
      'actor_name' => 'Контролер'
    )

    contact_connected = ContactsService.find(contact['id'])
    expect(contact_connected['disconnected']).to eq('нет')

    water_connected = WaterRegistryService.find(water['id'])
    expect(water_connected[:connection_act]).to eq('да')
    expect(water_connected[:connection_act_note]).to include(connect[:act_number])

    uute = Factories.create_uute_gspo(object_id: object_id, identifier: 'FLOW-001')
    UuteService.create_link(contact_id: contact['id'], uute_id: uute[:id])
    links = UuteDB.with_db { |db| UuteDB.links_for_uute(db, uute[:id]) }
    expect(links).not_to be_empty
  end
end
