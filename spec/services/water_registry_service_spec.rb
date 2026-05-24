# frozen_string_literal: true

require 'spreadsheet'
require_relative '../../services/water_registry_service'

RSpec.describe WaterRegistryService do
  let(:object_id) { Factories.build_registry_object(identifier: 'WATER-OBJ-1').to_i }

  describe 'CRUD' do
    it 'creates, finds and updates a row' do
      created = described_class.create(
        'actual_connection_point' => 'Точка Б',
        'payment' => 'да',
        'payment_date' => '2026-05-01'
      )
      id = created[:id]
      expect(id).to be > 0

      found = described_class.find(id)
      expect(found[:actual_connection_point]).to eq('Точка Б')

      updated = described_class.update(id, { 'note' => 'тестовая заметка' })
      expect(updated[:note]).to eq('тестовая заметка')
    end
  end

  describe '#list' do
    before do
      described_class.create(
        'actual_connection_point' => 'Т1',
        'payment' => 'да',
        'payment_date' => '2026-04-15'
      )
      described_class.create(
        'actual_connection_point' => 'Т2',
        'payment' => 'нет',
        'payment_date' => '2026-03-01'
      )
    end

    it 'filters by payment date range' do
      result = described_class.list(page: 0, payment_from: '2026-04-01', payment_to: '2026-05-31')
      dates = result[:records].map { |r| r[:payment_date] }
      expect(dates).to all(satisfy { |d| d >= '2026-04-01' && d <= '2026-05-31' })
    end
  end

  describe '#paid_rows' do
    it 'returns paid records for phoneogram' do
      described_class.create(
        'actual_connection_point' => 'Т оплата',
        'payment' => 'да',
        'payment_date' => '2026-05-10'
      )
      data = described_class.paid_rows(payment_from: '2026-05-01', payment_to: '2026-05-31')
      expect(data[:records]).not_to be_empty
    end
  end

  describe '#import_disconnections' do
    def write_disconnect_fixture(path)
      book = Spreadsheet::Workbook.new
      sheet = book.create_worksheet(name: 'БУ-1')
      sheet.row(0).replace(
        ['назначение', 'Наименование потребителей', 'Идентификатор', 'Акт отключения 2026г']
      )
      sheet.row(1).replace(['гспо', 'Тест', 'WATER-OBJ-1', 'Отключено по акту'])
      book.write(path)
    end

    it 'updates matching water rows from xls' do
      Factories.create_water_row(object_id: object_id, identifier: 'WATER-OBJ-1')
      path = File.join(SpecDatabase::SPEC_DIR, 'disconnect_import.xls')
      write_disconnect_fixture(path)

      result = described_class.import_disconnections(path, filename: 'disconnect_import.xls')
      expect(result[:matched]).to be >= 1
    end
  end
end
