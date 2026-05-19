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

# Запросим формат всей строки 42 (1-based) — это 0-based индекс 41. И чуть-чуть вокруг.
code, body = GoogleSheetsAPI.request(
  :get, doc, '',
  ranges: "#{latest_name}!A40:AZ55",
  fields: 'sheets(properties(sheetId,title,gridProperties),data(rowData(values(formattedValue,effectiveFormat(backgroundColor,borders)))))',
  includeGridData: 'true'
)
abort "fetch failed: #{code}" unless code == 200
data = JSON.parse(body)
target = data['sheets'].find { |s| s['properties']['sheetId'] == latest_id }
grid = target['properties']['gridProperties']
puts "gridProperties: rowCount=#{grid['rowCount']} colCount=#{grid['columnCount']}"

rd = target.dig('data', 0, 'rowData') || []
puts "\n--- rows 40-55, all 52 cols ---"
rd.each_with_index do |row, ri|
  cells = row['values'] || []
  next if cells.empty?
  # Найти ячейки с НЕ-белым фоном или с границами
  notable = []
  cells.each_with_index do |c, ci|
    bg = c.dig('effectiveFormat', 'backgroundColor') || {}
    r = (bg['red'] || 0).to_f.round(2)
    g = (bg['green'] || 0).to_f.round(2)
    b = (bg['blue'] || 0).to_f.round(2)
    borders = c.dig('effectiveFormat', 'borders') || {}
    bord = borders.keys.sort.map { |k| k[0] }.join
    is_white = (r == 1.0 && g == 1.0 && b == 1.0)
    is_default = (r.zero? && g.zero? && b.zero?)
    next if (is_white || is_default) && bord.empty?

    col_letter = GoogleSheetsAPI.column_letter(ci)
    notable << "[#{col_letter}] #{r}/#{g}/#{b} b=#{bord.empty? ? '-' : bord}"
  end
  puts "  row #{40 + ri}: #{notable.empty? ? 'clean' : notable.join(' | ')}"
end
