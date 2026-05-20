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

name_i = find_col.call(%w[наимен назван gspo гспо name])
uid_i = find_col.call(%w[uid юид идентификатор id])
raise 'columns not found' if name_i.nil? || uid_i.nil?

norm = ->(s) { s.to_s.strip }

src = {}
(2..sheet.last_row).each do |r|
  name = sheet.cell(r, name_i + 1).to_s
  uid = sheet.cell(r, uid_i + 1).to_s.strip
  next if name.strip.empty? || uid.empty?

src[norm.call(name)] = uid
end

db = SQLite3::Database.new(db_path)
db.results_as_hash = true
rows = db.execute("SELECT id, name, consumer, identifier FROM contacts WHERE category='gspo'")

matched = []
missing = []
contact_keys = {}

rows.each do |r|
  nm = r['name'].to_s.strip.empty? ? r['consumer'].to_s : r['name'].to_s
  key = norm.call(nm)
  contact_keys[key] = true
  if src.key?(key)
    matched << [r['id'], nm, r['identifier'].to_s, src[key]]
  else
    missing << [r['id'], nm]
  end
end

xlsx_unmatched = src.keys.reject { |k| contact_keys[k] }

updated = []
db.transaction
matched.each do |id, name, old_uid, new_uid|
  next if old_uid.to_s == new_uid.to_s

  db.execute('UPDATE contacts SET identifier = ?, updated_at = ? WHERE id = ?', [new_uid, Time.now.to_i, id])
  updated << [id, name, old_uid, new_uid]
end
db.commit

File.write(
  'storage/uid_update_report.json',
  {
    contacts_gspo: rows.size,
    matched: matched.size,
    updated: updated.size,
    missing: missing.size,
    missing_list: missing,
    xlsx_unmatched: xlsx_unmatched.size,
    xlsx_unmatched_list: xlsx_unmatched.first(100),
    updated_sample: updated.first(30)
  }.to_json
)

puts({ matched: matched.size, updated: updated.size, missing: missing.size }.to_json)
