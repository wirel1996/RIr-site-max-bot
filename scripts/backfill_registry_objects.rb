#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'
require_relative '../storage/water_registry_db'

def norm(value)
  value.to_s.strip
end

def key_for(identifier, name, address)
  id = norm(identifier).downcase
  nm = norm(name).downcase
  ad = norm(address).downcase
  [id, nm, ad].join('|')
end

created = 0
linked_contacts = 0
linked_uute = 0
linked_water = 0

registry_by_key = {}

ContactsDB.with_db do |db|
  db.execute('SELECT id, identifier, name, address FROM registry_objects').each do |row|
    registry_by_key[key_for(row['identifier'], row['name'], row['address'])] = row['id'].to_i
  end

  contacts = db.execute('SELECT id, identifier, name, address, object_id FROM contacts')
  contacts.each do |row|
    next if row['object_id'].to_i > 0

    key = key_for(row['identifier'], row['name'], row['address'])
    object_id = registry_by_key[key]
    unless object_id
      now = Time.now.to_i
      db.execute(
        'INSERT INTO registry_objects(name, address, identifier, source, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?)',
        [norm(row['name']), norm(row['address']), norm(row['identifier']), 'contacts', now, now]
      )
      object_id = db.last_insert_row_id
      registry_by_key[key] = object_id
      created += 1
    end
    db.execute('UPDATE contacts SET object_id = ?, updated_at = ? WHERE id = ?', [object_id, Time.now.to_i, row['id'].to_i])
    linked_contacts += 1
  end
end

UuteDB.with_db do |db|
  rows = db.execute('SELECT id, identifier, name, address, object_id FROM uute_objects')
  rows.each do |row|
    next if row['object_id'].to_i > 0

    key = key_for(row['identifier'], row['name'], row['address'])
    object_id = registry_by_key[key]
    if object_id
      db.execute('UPDATE uute_objects SET object_id = ?, updated_at = ? WHERE id = ?', [object_id, Time.now.to_i, row['id'].to_i])
      linked_uute += 1
    end
  end
end

WaterRegistryDB.with_db do |db|
  rows = db.execute('SELECT id, identifier, gspo_name, standalone_address, object_id FROM water_registry_rows')
  rows.each do |row|
    next if row['object_id'].to_i > 0

    key = key_for(row['identifier'], row['gspo_name'], row['standalone_address'])
    object_id = registry_by_key[key]
    if object_id
      db.execute('UPDATE water_registry_rows SET object_id = ?, updated_at = ? WHERE id = ?', [object_id, Time.now.to_i, row['id'].to_i])
      linked_water += 1
    end
  end
end

puts({ created: created, linked_contacts: linked_contacts, linked_uute: linked_uute, linked_water: linked_water }.inspect)
