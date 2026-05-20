# frozen_string_literal: true

require 'json'
require 'roo'
require 'sqlite3'

xlsx = 'C:/Users/Администратор/Desktop/ЮИД база.xlsx'
db = 'C:/max_bot/storage/contacts.db'

sheet = Roo::Spreadsheet.open(xlsx).sheet(0)
header = sheet.row(1).map { |c| c.to_s.strip.downcase }
uid_i = header.find_index { |h| h.include?('uid') || h.include?('юид') || h.include?('идентификатор') || h == 'id' }
raise 'uid column not found in xlsx' if uid_i.nil?

file_uids = []
(2..sheet.last_row).each do |r|
  uid = sheet.cell(r, uid_i + 1).to_s.strip
  file_uids << uid unless uid.empty?
end
file_counts = file_uids.tally

conn = SQLite3::Database.new(db)
conn.results_as_hash = true
rows = conn.execute("SELECT id, name, consumer, identifier FROM contacts WHERE category='gspo'")
db_rows = rows.map do |r|
  name = r['name'].to_s.strip.empty? ? r['consumer'].to_s : r['name'].to_s
  [r['id'], name, r['identifier'].to_s.strip]
end.reject { |(_, _, uid)| uid.empty? }
db_counts = db_rows.map { |x| x[2] }.tally

extras = []
db_counts.each do |uid, db_count|
  file_count = file_counts.fetch(uid, 0)
  next unless db_count > file_count

need = db_count - file_count
entries = db_rows.select { |x| x[2] == uid }.first(need)
extras.concat(entries.map { |id, name, u| { id: id, name: name, uid: u, db_count: db_count, file_count: file_count } })
end

puts JSON.pretty_generate(
  {
    db_total: rows.size,
    file_total: file_uids.size,
    db_unique_uids: db_counts.size,
    file_unique_uids: file_counts.size,
    extra_rows_count: extras.size,
    extra_rows: extras
  }
)
