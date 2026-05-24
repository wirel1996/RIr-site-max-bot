# frozen_string_literal: true

require_relative '../../services/contacts_service'

RSpec.describe ContactsService do
  describe 'phys CRUD' do
    it 'creates, finds, updates and deletes a contact' do
      created = Factories.create_phys_contact(name: 'Петров П.П.', phone: '79001112233')
      id = created['id']

      found = described_class.find(id)
      expect(found['name']).to eq('Петров П.П.')

      updated = described_class.update(id, { 'phone' => '79009998877' })
      expect(updated['phone']).to eq('79009998877')

      deleted = described_class.delete(id)
      expect(deleted['id']).to eq(id)
      expect(described_class.find(id)).to be_nil
    end
  end

  describe 'gspo with registry object' do
    it 'links contact to registry object on create' do
      contact = Factories.create_gspo_contact(
        name: 'Объект ГСПО',
        address: 'ул. Объектная, 10',
        identifier: 'GSPO-001'
      )
      expect(contact['object_id']).to be > 0
      expect(contact['identifier']).to eq('GSPO-001')
    end

    it 'strips forbidden fields on update' do
      contact = Factories.create_gspo_contact(name: 'Имя 1', identifier: 'GSPO-002')
      id = contact['id']
      original_name = contact['name']

      updated = described_class.update(id, {
        'name' => 'Новое имя',
        'address' => 'Новый адрес',
        'identifier' => 'NEW-UID',
        'phone' => '79005556677'
      })
      expect(updated['phone']).to eq('79005556677')
      expect(updated['name']).to eq(original_name)
    end
  end

  describe 'list and search' do
    before do
      3.times { |i| Factories.create_phys_contact(name: "Список #{i}") }
    end

    it 'paginates list' do
      rows, total = described_class.list('phys', page: 0, page_size: 2)
      expect(rows.size).to eq(2)
      expect(total).to be >= 3
    end

    it 'filters by query' do
      Factories.create_phys_contact(name: 'УникальныйПоискXYZ')
      rows, total = described_class.list('phys', page: 0, query: 'УникальныйПоискXYZ')
      expect(total).to eq(1)
      expect(rows.first['name']).to include('УникальныйПоискXYZ')
    end
  end
end
