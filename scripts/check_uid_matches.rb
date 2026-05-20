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
addr_i = find_col.call(%w[адрес address])
uid_i = find_col.call(%w[uid юид идентификатор id])

if name_i.nil? || uid_i.nil? || addr_i.nil?
  puts({ error: 'columns not found', header: header }.to_json)
  exit 1
end

norm = ->(s) { s.to_s.strip }

src = {}
src_total_rows = 0
(2..sheet.last_row).each do |r|
  name = sheet.cell(r, name_i + 1).to_s
  addr = sheet.cell(r, addr_i + 1).to_s
  uid = sheet.cell(r, uid_i + 1).to_s.strip
  next if name.strip.empty? || addr.strip.empty? || uid.empty?

  src_total_rows += 1
  src["#{norm.call(name)}||#{norm.call(addr)}"] = uid
end

db = SQLite3::Database.new(db_path)
db.results_as_hash = true
rows = db.execute("SELECT id, name, consumer, address, identifier FROM contacts WHERE category='gspo'")

contact_keys = {}
matched = []
missing = []

rows.each do |r|
  nm = r['name'].to_s.strip.empty? ? r['consumer'].to_s : r['name'].to_s
  addr = r['address'].to_s
  key = "#{norm.call(nm)}||#{norm.call(addr)}"
  contact_keys[key] = true
  if src.key?(key)
    matched << [r['id'], nm, addr, r['identifier'].to_s, src[key]]
  else
    missing << [r['id'], nm, addr]
  end
end

src_only = src.keys.reject { |k| contact_keys[k] }

puts(
  {
    xlsx_rows: src.size,
    xlsx_data_rows: src_total_rows,
    xlsx_last_row: sheet.last_row,
    contacts_gspo: rows.size,
    matched: matched.size,
    missing_in_xlsx_for_contacts: missing.size,
    xlsx_unmatched: src_only.size,
    sample_matches: matched.first(15),
    sample_missing: missing.first(15)
  }.to_json
)
