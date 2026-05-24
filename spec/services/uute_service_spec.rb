# frozen_string_literal: true

require_relative '../../storage/uute_db'
require_relative '../../services/uute_service'
require_relative '../../services/audit_log_service'

RSpec.describe UuteService do
  let(:registry_object_id) { Factories.build_registry_object(identifier: 'UUTE-OBJ').to_i }

  describe 'CRUD' do
    it 'creates and updates uute record' do
      created = Factories.create_uute_gspo(object_id: registry_object_id, name: 'Узел 1')
      id = created[:id]
      expect(created[:source_key]).to include('manual:gspo')

      updated = described_class.update(id, { 'contract_number' => 'Д-123' })
      expect(updated[:contract_number]).to eq('Д-123')
    end
  end

  describe '#submit_act' do
    let(:uute_id) do
      Factories.create_uute_gspo(
        object_id: registry_object_id,
        'admit_until' => '2026-12-31',
        'date_input_uute' => '2025-01-01'
      )[:id]
    end

    it 'submits input act with act number' do
      result = described_class.submit_act(
        uute_id,
        'act_kind' => 'input',
        'date_input_uute' => '2026-05-01',
        'seal_calculator' => 'П-1'
      )
      expect(result[:record][:act_number]).not_to be_empty
      expect(result[:record][:date_input_uute]).to eq('2026-05-01')
    end

    it 'does not change admit_until on check act' do
      described_class.submit_act(
        uute_id,
        'act_kind' => 'input',
        'date_input_uute' => '2026-01-01',
        'seal_calculator' => 'П-1'
      )
      before = described_class.find(uute_id)[:admit_until]

      described_class.submit_act(
        uute_id,
        'act_kind' => 'check',
        'check_date' => '2026-05-15'
      )
      after = described_class.find(uute_id)
      expect(after[:admit_until]).to eq(before)
      expect(after[:check_date]).to eq('2026-05-15')
    end
  end

  describe '#delete_act' do
    it 'reverts last input act when audit trail exists' do
      uute_id = Factories.create_uute_gspo(object_id: registry_object_id)[:id]
      before = described_class.find(uute_id)
      result = described_class.submit_act(
        uute_id,
        'act_kind' => 'input',
        'date_input_uute' => '2026-05-01',
        'seal_calculator' => 'П-1'
      )
      expect(result[:record][:act_number]).not_to be_empty

      AuditLogService.record_changes(
        actor: { login: 'rspec_admin', name: 'RSpec' },
        action: described_class.act_submit_audit_action('input'),
        entity_type: 'metering',
        entity_id: uute_id.to_s,
        entity_label: 'uute',
        before: before,
        after: result[:record],
        fields: result[:fields].map(&:to_s)
      )

      described_class.delete_act(uute_id, act_kind: 'input')
      expect(described_class.find(uute_id)[:act_number].to_s.strip).to be_empty
    end
  end

  describe 'act numbering' do
    it 'allocates sequential numbers per year' do
      uute_id = Factories.create_uute_gspo(object_id: registry_object_id)[:id]
      r1 = described_class.submit_act(
        uute_id,
        'act_kind' => 'check',
        'check_date' => '2026-03-01'
      )
      r2 = described_class.submit_act(
        uute_id,
        'act_kind' => 'check',
        'check_date' => '2026-04-01'
      )
      n1 = r1[:record][:act_number].to_i
      n2 = r2[:record][:act_number].to_i
      expect(n2).to eq(n1 + 1)
    end
  end

  describe '#create_link' do
    it 'links contact and uute' do
      contact = Factories.create_gspo_contact(identifier: 'LINK-OBJ')
      uute = Factories.create_uute_gspo(object_id: contact['object_id'])
      described_class.create_link(contact_id: contact['id'], uute_id: uute[:id])
      links = UuteDB.with_db { |db| UuteDB.links_for_uute(db, uute[:id]) }
      expect(links.map { |l| l['contact_id'].to_i }).to include(contact['id'].to_i)
    end
  end

  describe 'categories' do
    it 'lists seeded categories including gspo' do
      keys = described_class.category_records.map { |row| row['key'] }
      expect(keys).to include('gspo')
    end

    it 'creates, updates and deletes empty category' do
      created = described_class.create_category('label' => 'Тестовая группа', 'key' => 'test_group')
      expect(created['label']).to eq('Тестовая группа')

      updated = described_class.update_category('test_group', 'label' => 'Переименована')
      expect(updated['label']).to eq('Переименована')

      deleted = described_class.delete_category('test_group')
      expect(deleted['key']).to eq('test_group')
    end

    it 'rejects create in unknown category' do
      object_id = Factories.build_registry_object(identifier: 'BAD-CAT-SVC').to_i
      expect do
        described_class.create('unknown_cat_xyz', 'object_id' => object_id)
      end.to raise_error(ArgumentError, /Неизвестная/)
    end
  end

  describe '#delete_record' do
    it 'deletes uute and its links' do
      contact = Factories.create_gspo_contact(identifier: 'DEL-REC')
      uute = Factories.create_uute_gspo(object_id: contact['object_id'])
      described_class.create_link(contact_id: contact['id'], uute_id: uute[:id])

      row = described_class.delete_record(uute[:id])
      expect(row['id'].to_i).to eq(uute[:id])
      expect(described_class.find(uute[:id])).to be_nil

      links = UuteDB.with_db { |db| UuteDB.links_for_uute(db, uute[:id]) }
      expect(links).to be_empty
    end
  end
end
