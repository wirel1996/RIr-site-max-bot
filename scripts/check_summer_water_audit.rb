# frozen_string_literal: true

require 'sqlite3'

db = SQLite3::Database.new('C:/max_bot/storage/audit_log.db')
db.results_as_hash = true

rows = db.execute(
  "SELECT created_at, action, entity_id, entity_label, field, old_value, new_value " \
  "FROM audit_logs WHERE entity_type = 'summer_water' ORDER BY id DESC LIMIT 30"
)

rows.each do |r|
  puts [Time.at(r['created_at'].to_i), r['action'], r['entity_id'], r['field'], r['old_value'], r['new_value']].join(' | ')
end
