# frozen_string_literal: true

require 'csv'
require 'json'
require 'roo'
require 'sqlite3'

xlsx = 'C:/Users/Администратор/Desktop/ЮИД база.xlsx'
db = 'C:/max_bot/storage/contacts.db'
stamp = Time.now.strftime('%Y%m%d_%H%M%S')
out_csv = "storage/uid_duplicates_#{stamp}.csv"
out_json = "storage/uid_duplicates_#{stamp}.json"

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
  [r['id'], name.to_s.strip, r['identifier'].to_s.strip]
end.reject { |(_, _, uid)| uid.empty? }

db_counts = db_rows.map { |x| x[2] }.tally

groups = []
db_counts.each do |uid, db_count|
  file_count = file_counts.fetch(uid, 0)
  next unless db_count > file_count

entries = db_rows.select { |x| x[2] == uid }
  groups << {
    uid: uid,
    db_count: db_count,
    file_count: file_count,
    extra_rows: db_count - file_count,
    db_entries: entries.map { |id, name, _| { id: id, name: name } }
  }
end

groups.sort_by! { |g| [-g[:extra_rows], g[:uid]] }

File.open(out_csv, 'wb') { |f| f.write("\uFEFF") }
CSV.open(out_csv, 'ab', col_sep: ';', write_headers: true,
         headers: ['UID', 'Сколько в базе', 'Сколько в файле', 'Лишних строк в базе', 'ID в базе', 'Имя в базе']) do |csv|
  groups.each do |g|
    g[:db_entries].each do |e|
      csv << [g[:uid], g[:db_count], g[:file_count], g[:extra_rows], e[:id], e[:name]]
    end
  end
end

File.write(out_json, JSON.pretty_generate({ groups_count: groups.size, groups: groups }))
puts JSON.generate({ groups_count: groups.size, csv: out_csv, json: out_json })
