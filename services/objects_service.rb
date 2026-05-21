# frozen_string_literal: true

require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'
require_relative '../storage/water_registry_db'

module ObjectsService
  module_function

  def categories
    [
      { key: 'gspo', label: 'ГСПО' },
      { key: 'phys', label: 'Прочие ФЛ' }
    ]
  end

  def list(category, query: nil)
    q = query.to_s.strip.downcase
    ContactsDB.with_db do |db|
      rows = db.execute(
        "SELECT ro.* FROM registry_objects ro " \
        "WHERE ro.id IN (SELECT DISTINCT object_id FROM contacts WHERE category = ? AND object_id IS NOT NULL AND object_id > 0) " \
        "ORDER BY COALESCE(NULLIF(TRIM(ro.address), ''), ro.name, ''), ro.id",
        [category.to_s]
      )
      rows = rows.select do |row|
        next true if q.empty?
        [row['name'], row['address'], row['identifier']].any? { |v| v.to_s.downcase.include?(q) }
      end
      rows.map { |row| public_object(row) }
    end
  end

  def detail(id)
    object = ContactsDB.with_db { |db| ContactsDB.find_registry_object(db, id) }
    return nil unless object

    contacts = ContactsDB.with_db do |db|
      db.execute(
        "SELECT id, category, name, address, identifier FROM contacts WHERE object_id = ? ORDER BY category, COALESCE(NULLIF(TRIM(address), ''), name, ''), id",
        [id.to_i]
      )
    end
    uute = UuteDB.with_db do |db|
      db.execute(
        "SELECT id, category, name, address, identifier FROM uute_objects WHERE object_id = ? ORDER BY COALESCE(NULLIF(TRIM(address), ''), name, ''), id",
        [id.to_i]
      )
    end
    water = WaterRegistryDB.with_db do |db|
      db.execute(
        'SELECT id, gspo_name, standalone_address, identifier FROM water_registry_rows WHERE object_id = ? ORDER BY numeric_point(point_number), gspo_name, id',
        [id.to_i]
      )
    end

    {
      object: public_object(object),
      contacts: contacts.map { |r| { id: r['id'].to_i, category: r['category'], name: r['name'], address: r['address'], identifier: r['identifier'] } },
      uute: uute.map { |r| { id: r['id'].to_i, category: r['category'], name: r['name'], address: r['address'], identifier: r['identifier'] } },
      water: water.map { |r| { id: r['id'].to_i, gspo_name: r['gspo_name'], standalone_address: r['standalone_address'], identifier: r['identifier'] } }
    }
  end

  def public_object(row)
    {
      id: row['id'].to_i,
      name: row['name'],
      address: row['address'],
      identifier: row['identifier']
    }
  end
end
