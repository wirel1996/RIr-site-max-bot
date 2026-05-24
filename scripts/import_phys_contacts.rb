#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../services/phys_contacts_import_service'
require_relative '../storage/contacts_db'

DEFAULT_PATH = 'C:/Users/Администратор/Desktop/ФЛ информация телефоны.xlsx'

path = ARGV.find { |a| !a.start_with?('-') } || DEFAULT_PATH
dry_run = ARGV.include?('--dry-run')
auto_yes = ARGV.include?('--yes')

unless File.file?(path)
  warn "Файл не найден: #{path}"
  exit 1
end

rows = PhysContactsImportService.parse_file(path)
puts "Файл: #{path}"
puts "Строк для импорта: #{rows.size}"

if dry_run
  sample = rows.first
  if sample
    puts "Пример первой строки:"
    puts "  object: #{sample[:object].inspect}"
    puts "  contact: #{sample[:contact].inspect}"
  end
  puts 'Режим --dry-run: изменения в БД не выполнялись.'
  exit 0
end

unless auto_yes
  print "Удалить все контакты и объекты «Прочие ФЛ» и импортировать #{rows.size} записей? [y/N] "
  answer = $stdin.gets.to_s.strip.downcase
  unless %w[y yes д да].include?(answer)
    puts 'Отменено.'
    exit 0
  end
end

backup_dir = File.expand_path('../storage/backups', __dir__)
FileUtils.mkdir_p(backup_dir)
backup_path = File.join(backup_dir, "contacts-before-phys-import-#{Time.now.strftime('%Y%m%d_%H%M%S')}.db")
if File.exist?(ContactsDB.db_path)
  FileUtils.cp(ContactsDB.db_path, backup_path)
  puts "Backup: #{backup_path}"
end

stats = PhysContactsImportService.run(path: path, dry_run: false)
puts stats.inspect

ContactsDB.with_db do |db|
  total = ContactsDB.count_in_category(db, 'phys')
  linked = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'phys' AND object_id IS NOT NULL AND object_id > 0").to_i
  with_uid = db.get_first_value(<<~SQL).to_i
    SELECT COUNT(*)
    FROM contacts c
    JOIN registry_objects ro ON ro.id = c.object_id
    WHERE c.category = 'phys' AND TRIM(COALESCE(ro.identifier, '')) <> ''
  SQL
  puts "Итого phys: total=#{total} linked=#{linked} with_uid=#{with_uid}"
end
