# frozen_string_literal: true

require_relative '../../services/phys_contacts_import_service'
require_relative '../../services/contacts_service'
require_relative '../../storage/contacts_db'
require_relative '../../storage/uute_db'
require_relative '../../storage/water_registry_db'

RSpec.describe PhysContactsImportService do
  let(:fixture_path) { File.expand_path('../fixtures/files/phys_import_sample.xls', __dir__) }

  before(:all) do
    path = File.expand_path('../fixtures/files/phys_import_sample.xls', __dir__)
    unless File.exist?(path)
      system('ruby', File.expand_path('../../scripts/generate_phys_import_fixture.rb', __dir__), exception: true)
    end
  end

  describe '.parse_file' do
    it 'maps headers and skips empty rows' do
      rows = described_class.parse_file(fixture_path)
      expect(rows.size).to eq(2)

      first = rows.first
      expect(first[:object][:identifier]).to eq('11111111-1111-1111-1111-111111111111')
      expect(first[:object][:name]).to eq('ИП Тестов')
      expect(first[:object][:address]).to eq('ул. Тестовая, 1')
      expect(first[:contact][:manager]).to eq('Тестов Т.Т.')
      expect(first[:contact][:phone]).to eq('8-913-111-22-33')
      expect(first[:contact][:notes]).to eq('')
      expect(first[:contact][:email]).to eq('test@example.com')
      expect(first[:contact][:postal_address]).to eq('636000, Северск')
      expect(first[:contact][:metering_presence]).to eq('нет')

      second = rows.last
      expect(second[:contact][:notes]).to eq('Сидоров; Петров')
      expect(second[:contact][:phone]).to eq('89001234567')
      expect(second[:contact][:phone_alt]).to eq('89007654321')
    end
  end

  describe 'purge and import' do
    let(:registry_object_id) do
      ContactsDB.with_db do |db|
        ContactsDB.upsert_registry_object(
          db,
          name: 'Старый',
          address: 'Старый адрес',
          identifier: 'OLD-PHYS-UID',
          source: 'spec'
        )
      end
    end

    before do
      object_id = registry_object_id
      ContactsDB.with_db do |db|
        now = Time.now.to_i
        db.execute(
          <<~SQL,
            INSERT INTO contacts
              (category, consumer, manager, address, identifier, object_id, disconnected, updated_at)
            VALUES ('phys', 'Старый потребитель', 'Старый', 'Старый адрес', 'OLD-PHYS-UID', ?, 'нет', ?)
          SQL
          [object_id, now]
        )
        ContactsDB.create_switch_event(
          db,
          object_id: object_id,
          kind: 'disconnect',
          act_number: '1',
          event_date: '2026-01-01',
          place: 'test',
          seal_numbers: '1',
          actor_name: 'Tester'
        )
      end

      uute = Factories.create_uute_gspo(object_id: registry_object_id)
      @uute_id = uute[:id]
      Factories.create_water_row(object_id: registry_object_id)
    end

    it 'purges phys data, unlinks uute/water and imports linked contacts' do
      rows = described_class.parse_file(fixture_path).first(1)

      purge_stats = ContactsDB.with_db { |db| described_class.purge_phys!(db) }
      expect(purge_stats[:contacts]).to eq(1)
      expect(purge_stats[:objects]).to eq(1)
      expect(purge_stats[:switch_events]).to eq(1)
      expect(purge_stats[:unlinked_uute]).to eq(1)
      expect(purge_stats[:unlinked_water]).to eq(1)

      uute_row = UuteDB.with_db { |db| UuteDB.find(db, @uute_id) }
      expect(uute_row['object_id']).to be_nil

      import_stats = ContactsDB.with_db { |db| described_class.import!(db, rows) }
      expect(import_stats[:imported]).to eq(1)
      expect(import_stats[:skipped]).to eq(0)

      ContactsDB.with_db do |db|
        total = ContactsDB.count_in_category(db, 'phys')
        expect(total).to eq(1)

        contact = db.get_first_row("SELECT * FROM contacts WHERE category = 'phys'")
        expect(contact['object_id'].to_i).to be > 0
        expect(contact['consumer']).to eq('ИП Тестов')

        merged = ContactsService.send(:with_registry_object, contact, db: db)
        expect(merged['identifier']).to eq('11111111-1111-1111-1111-111111111111')
        expect(merged['address']).to eq('ул. Тестовая, 1')
      end
    end

    it 'skips duplicate identifiers in file' do
      duplicate_rows = [
        {
          object: { identifier: 'dup-uid-1111-1111-1111-111111111111', name: 'A', address: 'Addr 1' },
          contact: { consumer: 'A', manager: '', phone: '', phone_alt: '', email: '', postal_address: '', notes: '', metering_presence: '', source_row: 2 }
        },
        {
          object: { identifier: 'dup-uid-1111-1111-1111-111111111111', name: 'B', address: 'Addr 2' },
          contact: { consumer: 'B', manager: '', phone: '', phone_alt: '', email: '', postal_address: '', notes: '', metering_presence: '', source_row: 3 }
        }
      ]

      stats = ContactsDB.with_db { |db| described_class.import!(db, duplicate_rows) }
      expect(stats[:imported]).to eq(1)
      expect(stats[:skipped]).to eq(1)
      expect(stats[:warnings].size).to eq(1)
    end

    it 'skips completely empty rows' do
      empty_row = {
        object: { identifier: '', name: '', address: '' },
        contact: { consumer: '', manager: '', phone: '', phone_alt: '', email: '', postal_address: '', notes: '', metering_presence: '', source_row: 99 }
      }
      stats = ContactsDB.with_db { |db| described_class.import!(db, [empty_row]) }
      expect(stats[:imported]).to eq(0)
      expect(stats[:skipped]).to eq(1)
    end
  end
end
