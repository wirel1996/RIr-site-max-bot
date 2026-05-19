# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require 'dotenv/load' if File.exist?(File.expand_path('../.env', __dir__))
require_relative '../services/journal_service'
require_relative '../services/google_sheets_api'

JournalService.index_all(force: true)
meta = JournalService.instance_variable_get(:@cache)[:sheet_meta]
latest = meta.max_by { |_, m| m[:dates].keys.max.to_s }[0]
rows = GoogleSheetsAPI.read_range(JournalService.document_id, latest, 'A1:H1')

puts "Шапка листа '#{latest}':"
rows[0].each_with_index do |c, i|
  letter = ('A'.ord + i).chr
  puts "  col #{letter}: #{c.inspect}"
end
