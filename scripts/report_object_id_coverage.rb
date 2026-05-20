#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'
require_relative '../storage/water_registry_db'

report = {}

ContactsDB.with_db do |db|
  total = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'gspo'").to_i
  linked = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'gspo' AND object_id IS NOT NULL AND object_id > 0").to_i
  report[:contacts_gspo] = { total: total, linked: linked, unlinked: total - linked }
end

UuteDB.with_db do |db|
  total = db.get_first_value("SELECT COUNT(*) FROM uute_objects WHERE category = 'gspo'").to_i
  linked = db.get_first_value("SELECT COUNT(*) FROM uute_objects WHERE category = 'gspo' AND object_id IS NOT NULL AND object_id > 0").to_i
  report[:uute_gspo] = { total: total, linked: linked, unlinked: total - linked }
end

WaterRegistryDB.with_db do |db|
  total = db.get_first_value('SELECT COUNT(*) FROM water_registry_rows').to_i
  linked = db.get_first_value('SELECT COUNT(*) FROM water_registry_rows WHERE object_id IS NOT NULL AND object_id > 0').to_i
  report[:water_rows] = { total: total, linked: linked, unlinked: total - linked }
end

puts report.inspect
