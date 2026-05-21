#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../storage/contacts_db'

def blank?(value)
  value.to_s.strip.empty?
end

stats = {
  phys_total: 0,
  phys_with_uid: 0,
  phys_with_object_id: 0,
  phys_objects_blank_name_before: 0,
  scanned: 0,
  updated: 0,
  skipped_empty_consumer: 0,
  skipped_object_not_found: 0,
  skipped_object_name_not_blank: 0,
  phys_objects_blank_name_after: 0
}

ContactsDB.with_db do |db|
  stats[:phys_total] = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'phys'").to_i
  stats[:phys_with_uid] = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'phys' AND TRIM(COALESCE(identifier, '')) <> ''").to_i
  stats[:phys_with_object_id] = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'phys' AND object_id IS NOT NULL AND object_id > 0").to_i
  stats[:phys_objects_blank_name_before] = db.get_first_value(<<~SQL).to_i
    SELECT COUNT(*)
    FROM contacts c
    JOIN registry_objects ro ON ro.id = c.object_id
    WHERE c.category = 'phys'
      AND TRIM(COALESCE(ro.name, '')) = ''
  SQL

  rows = db.execute(<<~SQL)
    SELECT c.id AS contact_id,
           c.consumer AS consumer,
           c.identifier AS contact_identifier,
           c.object_id AS object_id,
           ro.name AS object_name
    FROM contacts c
    LEFT JOIN registry_objects ro ON ro.id = c.object_id
    WHERE c.category = 'phys'
      AND TRIM(COALESCE(c.identifier, '')) <> ''
  SQL

  now = Time.now.to_i
  rows.each do |row|
    stats[:scanned] += 1
    consumer = row['consumer'].to_s.strip
    if consumer.empty?
      stats[:skipped_empty_consumer] += 1
      next
    end

    object_id = row['object_id'].to_i
    if object_id <= 0
      stats[:skipped_object_not_found] += 1
      next
    end

    object_name = row['object_name'].to_s
    unless blank?(object_name)
      stats[:skipped_object_name_not_blank] += 1
      next
    end

    db.execute(
      'UPDATE registry_objects SET name = ?, updated_at = ? WHERE id = ?',
      [consumer, now, object_id]
    )
    stats[:updated] += 1
  end

  stats[:phys_objects_blank_name_after] = db.get_first_value(<<~SQL).to_i
    SELECT COUNT(*)
    FROM contacts c
    JOIN registry_objects ro ON ro.id = c.object_id
    WHERE c.category = 'phys'
      AND TRIM(COALESCE(ro.name, '')) = ''
  SQL
end

puts stats.inspect
