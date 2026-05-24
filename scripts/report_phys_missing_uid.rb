#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../storage/contacts_db'
require_relative '../storage/water_registry_db'

puts '=== Phys objects WITHOUT identifier ==='
ContactsDB.with_db do |db|
  rows = db.execute(<<~SQL)
    SELECT c.id AS contact_id, c.object_id, c.consumer, c.manager, c.phone, c.email,
           ro.name, ro.address, ro.identifier
    FROM contacts c
    JOIN registry_objects ro ON ro.id = c.object_id
    WHERE c.category = 'phys'
      AND (ro.identifier IS NULL OR TRIM(ro.identifier) = '')
    ORDER BY c.id
  SQL
  puts "Count: #{rows.size}"
  rows.each do |r|
    puts '---'
    puts "contact_id=#{r['contact_id']} object_id=#{r['object_id']}"
    puts "consumer: #{r['consumer']}"
    puts "address: #{r['address']}"
    puts "manager: #{r['manager']}"
    puts "phone: #{r['phone']}"
  end
end

puts
puts '=== Match for unlinked water (by identifier/name/address) ==='
WaterRegistryDB.with_db do |wdb|
  water = wdb.get_first_row('SELECT * FROM water_registry_rows WHERE id = 441')
  next unless water

  uid = water['identifier'].to_s.strip
  ContactsDB.with_db do |cdb|
    match = cdb.get_first_row(<<~SQL, [uid]) if !uid.empty?
      SELECT c.id, c.object_id, c.consumer, ro.address, ro.identifier
      FROM contacts c
      JOIN registry_objects ro ON ro.id = c.object_id
      WHERE c.category = 'phys' AND lower_ru(COALESCE(ro.identifier,'')) = lower_ru(?)
    SQL
    puts "By water UID: #{match ? "contact_id=#{match['id']} object_id=#{match['object_id']} #{match['consumer']}" : 'not found'}"

    like_name = "%#{water['gspo_name'].to_s.split.first}%"
    rows = cdb.execute(<<~SQL, [like_name, like_name])
      SELECT c.id, c.object_id, c.consumer, ro.address, ro.identifier
      FROM contacts c
      JOIN registry_objects ro ON ro.id = c.object_id
      WHERE c.category = 'phys'
        AND (lower_ru(COALESCE(c.consumer,'')) LIKE lower_ru(?) OR lower_ru(COALESCE(ro.name,'')) LIKE lower_ru(?))
      LIMIT 5
    SQL
    puts 'By name fragment:'
    rows.each { |r| puts "  contact_id=#{r['id']} object_id=#{r['object_id']} uid=#{r['identifier']} #{r['consumer']} — #{r['address']}" }
  end
end
WaterRegistryDB.with_db do |db|
  rows = db.execute(<<~SQL)
    SELECT id, gspo_name, standalone_address, identifier, object_id, actual_connection_point, point_number
    FROM water_registry_rows
    WHERE object_id IS NULL OR object_id <= 0
    ORDER BY id
  SQL
  puts "Total: #{rows.size}"
  rows.each do |r|
    puts '---'
    puts "water_id=#{r['id']} identifier=#{r['identifier']}"
    puts "name: #{r['gspo_name']}"
    puts "address: #{r['standalone_address']}"
    puts "point: #{r['actual_connection_point']} / #{r['point_number']}"
  end
end
