# frozen_string_literal: true

require 'securerandom'
require_relative '../../storage/contacts_db'
require_relative '../../storage/water_registry_db'
require_relative '../../services/contacts_service'
require_relative '../../services/registry_objects_service'

module Factories
  module_function

  def contact_defaults
    {
      'disconnected' => 'нет',
      'disconnected_date' => ''
    }
  end

  def build_registry_object(name: 'Тестовый объект', address: 'ул. Тестовая, 1', identifier: nil)
    uid = identifier || "UID-#{SecureRandom.hex(4)}"
    ContactsDB.with_db do |db|
      ContactsDB.upsert_registry_object(
        db,
        name: name,
        address: address,
        identifier: uid,
        source: 'spec'
      )
    end
  end

  def create_gspo_contact(name: 'ГСПО потребитель', address: 'ул. ГСПО, 2', identifier: nil, **attrs)
    uid = identifier || "GSPO-#{SecureRandom.hex(4)}"
    ContactsService.create(
      'gspo',
      contact_defaults.merge(
        'name' => name,
        'address' => address,
        'identifier' => uid,
        'phone' => '79001234567'
      ).merge(attrs.transform_keys(&:to_s))
    )
  end

  def create_phys_contact(name: 'Иванов И.И.', **attrs)
    ContactsService.create(
      'phys',
      contact_defaults.merge('name' => name, 'phone' => '79007654321').merge(attrs.transform_keys(&:to_s))
    )
  end

  def create_water_row(object_id:, **attrs)
    now = Time.now.to_i
    defaults = {
      'source_key' => "spec:water:#{SecureRandom.hex(6)}",
      'actual_connection_point' => 'Точка А',
      'point_number' => '1',
      'object_id' => object_id.to_i,
      'gspo_name' => 'Вода тест',
      'standalone_address' => 'ул. Водная, 3',
      'raw_json' => '{}',
      'imported_at' => now,
      'updated_at' => now
    }
    WaterRegistryDB.with_db do |db|
      WaterRegistryDB.create(db, defaults.merge(attrs.transform_keys(&:to_s)))
    end
  end

  def create_uute_gspo(object_id:, **attrs)
    require_relative '../../services/uute_service'
    UuteService.create(
      'gspo',
      {
        'object_id' => object_id.to_i,
        'name' => 'УУТЭ тест',
        'address' => 'ул. УУТЭ, 1',
        'identifier' => "UUTE-#{SecureRandom.hex(3)}"
      }.merge(attrs.transform_keys(&:to_s))
    )
  end
end
