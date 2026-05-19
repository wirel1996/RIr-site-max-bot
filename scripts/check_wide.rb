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
puts "Sheet: #{latest_name}"

code, body = GoogleSheetsAPI.request(
  :get, doc, '',
  ranges: "#{latest_name}!A1:AZ55",
  fields: 'sheets(properties(sheetId,title,gridProperties),data(rowData(values(formattedValue,effectiveFormat(backgroundColor,borders)))))',
  includeGridData: 'true'
)
data = JSON.parse(body)
target = data['sheets'].find { |s| s['properties']['sheetId'] == latest_id }
rd = target.dig('data', 0, 'rowData') || []
puts "Row | non-white-bg or bordered cells past col J"
rd.each_with_index do |row, ri|
  cells = row['values'] || []
  notes = []
  cells.each_with_index do |c, ci|
    next if ci < 10  # column K = index 10 (0-based)
    bg = c.dig('effectiveFormat', 'backgroundColor') || {}
    r = (bg['red'] || 0).to_f.round(2)
    g = (bg['green'] || 0).to_f.round(2)
    b = (bg['blue'] || 0).to_f.round(2)
    borders = c.dig('effectiveFormat', 'borders') || {}
    bord = borders.keys.sort.map { |k| k[0] }.join
    is_default = (r.zero? && g.zero? && b.zero?)
    is_white = (r == 1.0 && g == 1.0 && b == 1.0)
    next if (is_white || is_default) && bord.empty?
    notes << "[#{GoogleSheetsAPI.column_letter(ci)}]#{r}/#{g}/#{b}/#{bord.empty? ? '-' : bord}"
  end
  next if notes.empty?
  puts "  row #{ri + 1}: #{notes.join(' ')}"
end
