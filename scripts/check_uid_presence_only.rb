# frozen_string_literal: true

require 'json'
require 'roo'
require 'sqlite3'

xlsx = 'C:/Users/Администратор/Desktop/ЮИД база.xlsx'
db_path = 'C:/max_bot/storage/contacts.db'

sheet = Roo::Spreadsheet.open(xlsx).sheet(0)
header = sheet.row(1).map { |c| c.to_s.strip }

find_col = lambda do |keys|
  header.find_index do |h|
    hh = h.downcase
    keys.any? { |k| hh.include?(k) }
  end
end

uid_i = find_col.call(%w[uid юид идентификатор id])
raise 'UID column not found in XLSX' if uid_i.nil?

norm_uid = ->(v) { v.to_s.strip }

xlsx_uids = {}
(2..sheet.last_row).each do |r|
  uid = norm_uid.call(sheet.cell(r, uid_i + 1))
  next if uid.empty?
  xlsx_uids[uid] = true
end

db = SQLite3::Database.new(db_path)
db.results_as_hash = true
rows = db.execute("SELECT id, name, consumer, identifier FROM contacts WHERE category='gspo'")

db_uid_rows = []
rows.each do |r|
  uid = norm_uid.call(r['identifier'])
  next if uid.empty?
  name = r['name'].to_s.strip.empty? ? r['consumer'].to_s : r['name'].to_s
  db_uid_rows << [r['id'], name, uid]
end

missing_in_xlsx = db_uid_rows.reject { |(_, _, uid)| xlsx_uids.key?(uid) }

report = {
  xlsx_uid_count: xlsx_uids.size,
  db_gspo_count: rows.size,
  db_with_uid_count: db_uid_rows.size,
  db_uids_missing_in_xlsx_count: missing_in_xlsx.size,
  db_uids_missing_in_xlsx: missing_in_xlsx
}

File.write('storage/uid_presence_report.json', JSON.pretty_generate(report))
puts JSON.generate(report)
