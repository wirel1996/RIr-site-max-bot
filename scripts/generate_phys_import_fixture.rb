# frozen_string_literal: true

require 'spreadsheet'
require 'fileutils'

Spreadsheet.client_encoding = 'UTF-8'

dir = File.expand_path('../spec/fixtures/files', __dir__)
FileUtils.mkdir_p(dir)

book = Spreadsheet::Workbook.new
sheet = book.create_worksheet(name: 'phys')
headers = [
  'Идентификатор', 'Наименование потребителей', 'Наличие ПУ',
  'Адреса отдельностоящих объектов', 'Ф.И.О. руководителя', 'Ответственные лица',
  'телефон', 'альтернативный телефон', 'Электронная почта', 'почтовый адрес'
]
headers.each_with_index { |h, i| sheet[0, i] = h }

rows = [
  ['11111111-1111-1111-1111-111111111111', 'ИП Тестов', 'нет', 'ул. Тестовая, 1', 'Тестов Т.Т.', '8-913-111-22-33', '', '', 'test@example.com', '636000, Северск'],
  ['22222222-2222-2222-2222-222222222222', 'ИП Второй', 'да', 'ул. Другая, 2', 'Второй В.В.', 'Сидоров; Петров', '89001234567', '89007654321', 'v2@example.com', '636001, Северск'],
  ['', '', '', '', '', '', '', '', '', '']
]
rows.each_with_index do |row, idx|
  row.each_with_index { |val, col| sheet[idx + 1, col] = val }
end

path = File.join(dir, 'phys_import_sample.xls')
book.write(path)
puts path
