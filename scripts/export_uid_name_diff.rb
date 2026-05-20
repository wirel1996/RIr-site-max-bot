# frozen_string_literal: true

require 'csv'
require 'json'
require 'roo'
require 'sqlite3'

xlsx = 'C:/Users/Администратор/Desktop/ЮИД база.xlsx'
db_path = 'C:/max_bot/storage/contacts.db'
out_csv = 'storage/uid_name_diff.csv'
out_json = 'storage/uid_name_diff.json'

sheet = Roo::Spreadsheet.open(xlsx).sheet(0)
header = sheet.row(1).map { |c| c.to_s.strip }

find_col = lambda do |keys|
  header.find_index do |h|
    hh = h.downcase
    keys.any? { |k| hh.include?(k) }
  end
end

name_i = find_col.call(%w[наимен назван gspo гспо name])
uid_i = find_col.call(%w[uid юид идентификатор id])
raise 'columns not found in XLSX' if name_i.nil? || uid_i.nil?

norm = ->(s) { s.to_s.strip.gsub(/\s+/, ' ') }

file_by_uid = {}
(2..sheet.last_row).each do |r|
  name = norm.call(sheet.cell(r, name_i + 1))
  uid = norm.call(sheet.cell(r, uid_i + 1))
  next if name.empty? || uid.empty?

  file_by_uid[uid] = name
end

db = SQLite3::Database.new(db_path)
db.results_as_hash = true
rows = db.execute("SELECT id, name, consumer, identifier FROM contacts WHERE category='gspo'")

diffs = []
rows.each do |r|
  uid = norm.call(r['identifier'])
  next if uid.empty?
  next unless file_by_uid.key?(uid)

  db_name = norm.call(r['name'].to_s.strip.empty? ? r['consumer'] : r['name'])
  file_name = file_by_uid[uid]
  next if db_name == file_name

  diffs << {
    id: r['id'],
    uid: uid,
    file_name: file_name,
    db_name: db_name
  }
end

CSV.open(out_csv, 'wb', write_headers: true, headers: ['Имя(файл excel)', 'UID', 'Имя(база)']) do |csv|
  diffs.each { |d| csv << [d[:file_name], d[:uid], d[:db_name]] }
end

File.write(out_json, JSON.pretty_generate({ count: diffs.size, rows: diffs }))
puts JSON.generate({ count: diffs.size, csv: out_csv, json: out_json })
