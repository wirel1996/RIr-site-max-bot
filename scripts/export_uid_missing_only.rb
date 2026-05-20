# frozen_string_literal: true

require 'csv'
require 'json'

source_json = Dir['storage/uid_full_export_*.json'].max
raise 'uid_full_export JSON not found' unless source_json

data = JSON.parse(File.read(source_json, encoding: 'UTF-8'))
rows = Array(data['rows'])
missing = rows.select { |r| r['uid_found_in_file'] == false }

stamp = Time.now.strftime('%Y%m%d_%H%M%S')
out_csv = "storage/uid_missing_only_#{stamp}.csv"
out_json = "storage/uid_missing_only_#{stamp}.json"

File.open(out_csv, 'wb') { |f| f.write("\uFEFF") }
CSV.open(out_csv, 'ab', col_sep: ';', write_headers: true, headers: ['ID', 'UID', 'Имя(база)']) do |csv|
  missing.each { |r| csv << [r['id'], r['uid'], r['db_name']] }
end

File.write(out_json, JSON.pretty_generate({ count: missing.size, rows: missing }))
puts JSON.generate({ count: missing.size, csv: out_csv, json: out_json, source: source_json })
