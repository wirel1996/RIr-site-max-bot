# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require 'dotenv/load' if File.exist?(File.expand_path('../.env', __dir__))
require_relative '../services/journal_service'
require_relative '../services/google_sheets_api'

doc = JournalService.document_id
JournalService.index_all(force: true)
meta = JournalService.instance_variable_get(:@cache)[:sheet_meta]
latest_name = meta.max_by { |_, m| m[:dates].keys.max.to_s }[0]
latest_id = meta[latest_name][:sheet_id]
puts "Sheet: #{latest_name} (id=#{latest_id})"

# 1) Значения rows 1..55
values = GoogleSheetsAPI.read_range(doc, latest_name, 'A1:H55')
puts "\n--- VALUES rows 1-55 (only non-empty) ---"
values.each_with_index do |r, i|
  next if r.nil? || r.compact.all?(&:empty?)
  puts "  row #{i + 1}: #{r.inspect}"
end

# 2) Полное форматирование 1..55
code, body = GoogleSheetsAPI.request(
  :get, doc, '',
  ranges: "#{latest_name}!A1:H55",
  fields: 'sheets(properties(sheetId,title),data(rowData(values(formattedValue,effectiveFormat(backgroundColor,borders)))))',
  includeGridData: 'true'
)
abort "fetch failed: #{code} #{body[0, 200]}" unless code == 200
data = JSON.parse(body)
target = data['sheets'].find { |s| s['properties']['sheetId'] == latest_id }
abort 'no sheet' unless target
rd = target.dig('data', 0, 'rowData') || []
puts "\n--- FORMAT rows 1-55: bg + borders + value ---"
rd.each_with_index do |row, ri|
  cells = row['values'] || []
  next if cells.empty?
  parts = cells.first(8).map.with_index do |c, ci|
    bg = c.dig('effectiveFormat', 'backgroundColor') || {}
    r = (bg['red'] || 0).to_f.round(2)
    g = (bg['green'] || 0).to_f.round(2)
    b = (bg['blue'] || 0).to_f.round(2)
    borders = c.dig('effectiveFormat', 'borders') || {}
    bord = borders.keys.sort.map { |k| k[0] }.join
    val = c['formattedValue'].to_s
    "[#{('A'.ord + ci).chr}] #{r}/#{g}/#{b} b=#{bord.empty? ? '-' : bord} v=#{val.inspect}"
  end
  puts "  row #{format('%2d', ri + 1)}: #{parts.join(' | ')}"
end
