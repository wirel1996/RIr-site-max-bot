# frozen_string_literal: true

require 'sqlite3'

db = SQLite3::Database.new('C:/max_bot/storage/uute.db')
db.results_as_hash = true

rows = db.execute(
  "SELECT r.id, r.name, r.address, r.identifier " \
  'FROM uute_objects r ' \
  'LEFT JOIN uute_contact_links l ON l.uute_id = r.id ' \
  'WHERE l.uute_id IS NULL ' \
  'ORDER BY r.id'
)

puts "count=#{rows.size}"
rows.each do |r|
  puts "#{r['id']} | #{r['name']} | #{r['address']} | #{r['identifier']}"
end
