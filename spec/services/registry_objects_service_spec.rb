# frozen_string_literal: true

require_relative '../../services/registry_objects_service'

RSpec.describe RegistryObjectsService do
  let(:object_id) { Factories.build_registry_object(name: 'Реестр', identifier: 'REG-100').to_i }

  describe '#update' do
    it 'updates name, address and identifier' do
      before_row, after_row = described_class.update(object_id, {
        'name' => 'Новое название',
        'address' => 'Новый адрес',
        'identifier' => 'REG-101'
      })
      expect(before_row[:identifier]).to eq('REG-100')
      expect(after_row[:name]).to eq('Новое название')
      expect(after_row[:identifier]).to eq('REG-101')
    end

    it 'rejects empty identifier' do
      expect {
        described_class.update(object_id, { 'identifier' => '' })
      }.to raise_error(ArgumentError, /UID/)
    end
  end

  describe '#find' do
    it 'returns registry object' do
      row = described_class.find(object_id)
      expect(row[:id]).to eq(object_id)
    end
  end
end
