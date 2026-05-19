# frozen_string_literal: true

require 'roo'
require 'zip'

path = 'C:/Users/Администратор/Desktop/Реестр заявлений на подвчу воды на лето ГСПО 2026 (2).xlsx'
xlsx = Roo::Excelx.new(path)

puts "sheets: #{xlsx.sheets.inspect}"
xlsx.sheets.each do |sheet_name|
  xlsx.default_sheet = sheet_name
  puts "--- #{sheet_name} rows=#{xlsx.last_row} cols=#{xlsx.last_column}"
  (1..[xlsx.last_row.to_i, 20].min).each do |row|
    vals = (1..xlsx.last_column.to_i).map do |col|
      cell = xlsx.cell(row, col)
      next nil if cell.nil? || cell.to_s.strip.empty?

      "#{Roo::Utils.number_to_letter(col)}=#{cell.inspect}"
    end.compact
    puts "row #{row}: #{vals.join(' | ')}" unless vals.empty?
  end
end

puts '--- formulas'
Zip::File.open(path) do |zip|
  shared = {}
  shared_entry = zip.glob('xl/sharedStrings.xml').first
  if shared_entry
    xml = shared_entry.get_input_stream.read
    xml.scan(/<si>(.*?)<\/si>/m).each_with_index do |(si), idx|
      shared[idx] = si.scan(/<t[^>]*>(.*?)<\/t>/m).flatten.join.gsub(/&quot;/, '"').gsub(/&amp;/, '&').gsub(/&lt;/, '<').gsub(/&gt;/, '>')
    end
  end

  zip.glob('xl/worksheets/sheet*.xml').each do |entry|
    xml = entry.get_input_stream.read
    puts "sheet xml: #{entry.name}"
    xml.scan(/<c[^>]*r="([^"]+)"[^>]*>(.*?)<\/c>/m).each do |ref, body|
      next unless body.include?('<f')
      next unless ref.match?(/\A[A-Z]+(2|3|4|46|56|112|163)\z/)

      formula = body[/<f[^>]*>(.*?)<\/f>/m, 1].to_s
      value = body[/<v>(.*?)<\/v>/m, 1].to_s
      puts "  #{ref}: =#{formula} -> #{value}"
    end
  end
end
