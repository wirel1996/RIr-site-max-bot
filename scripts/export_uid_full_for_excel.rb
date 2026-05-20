# frozen_string_literal: true

require 'csv'
require 'json'
require 'roo'
require 'sqlite3'

xlsx = 'C:/Users/Администратор/Desktop/ЮИД база.xlsx'
db_path = 'C:/max_bot/storage/contacts.db'
stamp = Time.now.strftime('%Y%m%d_%H%M%S')
out_csv = "storage/uid_full_export_#{stamp}.csv"
out_json = "storage/uid_full_export_#{stamp}.json"

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
rows = db.execute("SELECT id, name, consumer, identifier FROM contacts WHERE category='gspo' ORDER BY id")

export_rows = rows.map do |r|
  uid = norm.call(r['identifier'])
  db_name = norm.call(r['name'].to_s.strip.empty? ? r['consumer'] : r['name'])
  file_name = uid.empty? ? '' : file_by_uid[uid].to_s
  {
    id: r['id'],
    file_name: file_name,
    uid: uid,
    db_name: db_name,
    uid_found_in_file: !file_name.empty?
  }
end

# UTF-8 BOM so Excel opens Russian text correctly on Windows.
File.open(out_csv, 'wb') { |f| f.write("\uFEFF") }
CSV.open(out_csv, 'ab', col_sep: ';', write_headers: true, headers: ['ID', 'Имя(файл excel)', 'UID', 'Имя(база)', 'UID есть в файле']) do |csv|
  export_rows.each do |e|
    csv << [e[:id], e[:file_name], e[:uid], e[:db_name], e[:uid_found_in_file] ? 'Да' : 'Нет']
  end
end

File.write(out_json, JSON.pretty_generate({ count: export_rows.size, rows: export_rows }))
puts JSON.generate({ count: export_rows.size, csv: out_csv, json: out_json })
