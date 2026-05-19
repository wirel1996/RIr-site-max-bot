# frozen_string_literal: true
# Утилита: 1) Удаляет самый «новый» лист (max start date) из таблицы журнала.
#          2) Создаёт следующую неделю через JournalService.create_next_week.
#          3) Считывает форматирование новой вкладки и распечатывает,
#             какие строки имеют какой backgroundColor — проверка «только 2,10,18,26,34 серые».

$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require 'dotenv/load' if File.exist?(File.expand_path('../.env', __dir__))
require_relative '../services/journal_service'
require_relative '../services/google_sheets_api'

abort 'JournalService not configured' unless JournalService.enabled?

doc = JournalService.document_id
idx = JournalService.index_all(force: true)

mondays = idx[:by_date].keys.map { |iso| Date.iso8601(iso) rescue nil }.compact.sort
puts "Latest known monday: #{mondays.last}"

# Найти лист, которому принадлежит самый поздний понедельник
latest = mondays.last
sheet_name_to_delete = idx[:by_date][latest.iso8601][:sheet]
puts "Sheet for latest monday: #{sheet_name_to_delete}"

# Только если в этом листе РОВНО одна неделя — удалим лист целиком.
dates_in_sheet = idx[:by_date].select { |_, m| m[:sheet] == sheet_name_to_delete }.keys.sort
puts "Dates in that sheet: #{dates_in_sheet.size} (#{dates_in_sheet.first}..#{dates_in_sheet.last})"

if dates_in_sheet.size <= 5
  sheet_id = idx[:sheet_meta][sheet_name_to_delete][:sheet_id]
  puts "Deleting sheet '#{sheet_name_to_delete}' (id=#{sheet_id})..."
  GoogleSheetsAPI.request(
    :post, doc, ':batchUpdate', {},
    requests: [{ deleteSheet: { sheetId: sheet_id } }]
  )
  puts "Deleted."
else
  puts "Sheet has more than 1 week — skipping delete."
end

# Forсе-refresh кэша
JournalService.index_all(force: true)

ok, result = JournalService.create_next_week
abort "create_next_week failed: #{result}" unless ok

new_sheet = result[:sheet]
new_start = result[:start]
puts "Created sheet: #{new_sheet} (start=#{new_start})"

# Получим sheetId нового листа
JournalService.index_all(force: true)
new_meta = JournalService.instance_variable_get(:@cache)[:sheet_meta][new_sheet]
abort 'no meta for new sheet' unless new_meta
new_sheet_id = new_meta[:sheet_id]

# Запросим форматирование первых 45 строк нового листа
code, body = GoogleSheetsAPI.request(
  :get, doc, '',
  {
    ranges: "#{new_sheet}!A1:H45",
    fields: 'sheets(properties(sheetId,title),data(rowData(values(effectiveFormat(backgroundColor)))))',
    includeGridData: 'true'
  }
)
abort "fetch failed: #{code}" unless code == 200
data = JSON.parse(body)
target_sheet = data['sheets'].find { |s| s['properties']['sheetId'] == new_sheet_id }
abort 'target sheet not found in response' unless target_sheet

rows = target_sheet.dig('data', 0, 'rowData') || []
puts "\n--- Backgrounds (row 1-based, first 8 cells) ---"
puts "Expecting GREY at rows: 2,10,18,26,34"
rows.each_with_index do |row, ri|
  next if ri >= 45
  cells = row['values'] || []
  bgs = cells.first(8).map do |c|
    bg = c.dig('effectiveFormat', 'backgroundColor') || {}
    r = (bg['red'] || 0).to_f.round(2)
    g = (bg['green'] || 0).to_f.round(2)
    b = (bg['blue'] || 0).to_f.round(2)
    "#{r}/#{g}/#{b}"
  end
  classification = if bgs.empty?
                     'EMPTY'
                   elsif bgs.all? { |s| s == '1.0/1.0/1.0' || s == '0.0/0.0/0.0' && bgs.uniq.size == 1 }
                     'WHITE'
                   elsif bgs.all? { |s| s == bgs.first }
                     bgs.first
                   else
                     "MIXED: #{bgs.uniq.join(' ')}"
                   end
  marker = [2, 10, 18, 26, 34].include?(ri + 1) ? '<<< expected GREY' : ''
  puts "  row #{format('%2d', ri + 1)}: #{classification.ljust(40)} #{marker}"
end
