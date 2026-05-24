# frozen_string_literal: true

require_relative '../../services/objects_service'
require_relative '../../services/contacts_service'
require_relative '../../services/water_registry_service'
require_relative '../../storage/contacts_db'

RSpec.describe ObjectsService do
  let!(:contact) { Factories.create_gspo_contact(name: 'ГСПО SW', address: 'ул. SW, 1', identifier: 'SW-OBJ-1') }
  let(:registry_object_id) { contact['object_id'] }
  let!(:water_row) { Factories.create_water_row(object_id: registry_object_id) }

  describe '#create_switch_event' do
    it 'disconnects contacts and sets water note without third_party flag' do
      event = described_class.create_switch_event(
        registry_object_id,
        'kind' => 'disconnect',
        'event_date' => '21.05.2026',
        'place' => 'ввод',
        'seal_numbers' => %w[111 222],
        'actor_name' => 'Инженер'
      )
      expect(event[:kind]).to eq('disconnect')
      expect(event[:act_number]).not_to be_empty

      refreshed = ContactsService.find(contact['id'])
      expect(refreshed['disconnected']).to eq('да')
      expect(refreshed['disconnected_date']).to eq('21.05.2026')

      water = WaterRegistryService.find(water_row['id'])
      expect(water[:third_party_disconnection_note]).to include('Отключено')
      expect(water[:third_party_disconnection_note]).to include(event[:act_number])
      expect(water[:third_party_disconnection].to_s.strip).to be_empty
    end

    it 'connects contacts and sets connection act on water' do
      described_class.create_switch_event(
        registry_object_id,
        'kind' => 'disconnect',
        'event_date' => '01.05.2026',
        'place' => 'ввод',
        'actor_name' => 'Инженер'
      )

      event = described_class.create_switch_event(
        registry_object_id,
        'kind' => 'connect',
        'event_date' => '21.05.2026',
        'actor_name' => 'Инженер'
      )

      refreshed = ContactsService.find(contact['id'])
      expect(refreshed['disconnected']).to eq('нет')

      water = WaterRegistryService.find(water_row['id'])
      expect(water[:connection_act]).to eq('да')
      expect(water[:connection_act_note]).to include('Включено')
      expect(water[:connection_act_note]).to include(event[:act_number])
    end
  end

  describe '#resync_from_switch_events!' do
    it 'restores contact and water from latest switch event' do
      described_class.create_switch_event(
        registry_object_id,
        'kind' => 'disconnect',
        'event_date' => '10.05.2026',
        'place' => 'ввод',
        'actor_name' => 'Инженер'
      )

      ContactsDB.with_db do |db|
        db.execute(
          "UPDATE contacts SET disconnected = 'нет' WHERE object_id = ?",
          [registry_object_id]
        )
      end

      described_class.resync_from_switch_events!(registry_object_id)

      refreshed = ContactsService.find(contact['id'])
      expect(refreshed['disconnected']).to eq('да')
    end
  end

  describe 'switch act authors' do
    it 'lists users with position' do
      authors = UsersService.switch_act_authors
      logins = authors.map { |a| a[:login] }
      expect(logins).to include('rspec_author')
    end

    it 'resolves author by login' do
      author = UsersService.resolve_switch_act_author('rspec_author')
      expect(author[:position]).to eq('Инженер')
    end
  end

  describe '#switch_events_export_rows' do
    it 'exports full rows with address and UID' do
      described_class.create_switch_event(
        registry_object_id,
        'kind' => 'disconnect',
        'event_date' => '21.05.2026',
        'place' => 'ввод',
        'actor_name' => 'Инженер'
      )

      payload = described_class.switch_events_export_rows('gspo', mode: 'full')
      expect(payload[:headers]).to include('UID')
      expect(payload[:rows]).not_to be_empty
      expect(payload[:rows].first[1]).to eq('SW-OBJ-1')
    end
  end
end
