# frozen_string_literal: true

require_relative '../../services/objects_service'
require_relative '../../services/contacts_service'
require_relative '../../services/water_registry_service'

RSpec.describe 'Regressions' do
  describe 'gspo contact forbidden fields' do
    it 'ignores name/address/identifier on service update' do
      contact = Factories.create_gspo_contact(
        name: 'Регресс имя',
        address: 'Регресс адрес',
        identifier: 'REG-GSPO-1'
      )
      updated = ContactsService.update(contact['id'], {
        'name' => 'Другое',
        'address' => 'Другой адрес',
        'identifier' => 'HACK',
        'phone' => '79000001122'
      })
      expect(updated['name']).to eq('Регресс имя')
      expect(updated['identifier']).to eq('REG-GSPO-1')
      expect(updated['phone']).to eq('79000001122')
    end
  end

  describe 'disconnect water sync' do
    it 'sets note only, not third_party_disconnection=да' do
      contact = Factories.create_gspo_contact(identifier: 'REG-WATER-1')
      object_id = contact['object_id']
      water = Factories.create_water_row(object_id: object_id, third_party_disconnection: '')

      ObjectsService.create_switch_event(
        object_id,
        'kind' => 'disconnect',
        'event_date' => '21.05.2026',
        'place' => 'шкаф',
        'actor_name' => 'Тест'
      )

      row = WaterRegistryService.find(water['id'])
      expect(row[:third_party_disconnection_note]).to match(/Отключено/)
      expect(row[:third_party_disconnection].to_s.strip.downcase).not_to eq('да')
    end
  end
end
