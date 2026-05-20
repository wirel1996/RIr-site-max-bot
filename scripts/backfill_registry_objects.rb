#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'
require_relative '../storage/water_registry_db'

def norm(value)
  value.to_s.strip
end

def key_for_name_address(name, address)
  [norm(name).downcase, norm(address).downcase].join('|')
end

created = 0
linked_contacts = 0
linked_uute = 0
linked_water = 0

registry_by_uid = {}
registry_uid_counts = Hash.new(0)
registry_by_name_address = {}

ContactsDB.with_db do |db|
  db.execute('SELECT id, identifier, name, address FROM registry_objects').each do |row|
    rid = row['id'].to_i
    uid = norm(row['identifier']).downcase
    registry_uid_counts[uid] += 1 unless uid.empty?
    registry_by_uid[uid] = rid unless uid.empty?
    registry_by_name_address[key_for_name_address(row['name'], row['address'])] = rid
  end

  contacts = db.execute('SELECT id, identifier, name, address, object_id FROM contacts')
  contacts.each do |row|
    next if row['object_id'].to_i > 0

    uid = norm(row['identifier']).downcase
    object_id = if !uid.empty? && registry_uid_counts[uid] == 1
                  registry_by_uid[uid]
                else
                  registry_by_name_address[key_for_name_address(row['name'], row['address'])]
                end
    unless object_id
      now = Time.now.to_i
      db.execute(
        'INSERT INTO registry_objects(name, address, identifier, source, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?)',
        [norm(row['name']), norm(row['address']), norm(row['identifier']), 'contacts', now, now]
      )
      object_id = db.last_insert_row_id
      registry_by_name_address[key_for_name_address(row['name'], row['address'])] = object_id
      unless uid.empty?
        registry_uid_counts[uid] += 1
        registry_by_uid[uid] = object_id if registry_uid_counts[uid] == 1
      end
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

    uid = norm(row['identifier']).downcase
    object_id = if !uid.empty? && registry_uid_counts[uid] == 1
                  registry_by_uid[uid]
                else
                  registry_by_name_address[key_for_name_address(row['name'], row['address'])]
                end
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

    uid = norm(row['identifier']).downcase
    object_id = if !uid.empty? && registry_uid_counts[uid] == 1
                  registry_by_uid[uid]
                else
                  registry_by_name_address[key_for_name_address(row['gspo_name'], row['standalone_address'])]
                end
    if object_id
      db.execute('UPDATE water_registry_rows SET object_id = ?, updated_at = ? WHERE id = ?', [object_id, Time.now.to_i, row['id'].to_i])
      linked_water += 1
    end
  end
end

puts({ created: created, linked_contacts: linked_contacts, linked_uute: linked_uute, linked_water: linked_water }.inspect)
