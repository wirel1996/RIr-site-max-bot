# frozen_string_literal: true

require 'fileutils'
require_relative '../storage/contacts_db'

db_path = ContactsDB.db_path
backup_path = "#{db_path}.bak-iglakovo-#{Time.now.strftime('%Y%m%d%H%M%S')}"

FileUtils.cp(db_path, backup_path)
puts "Backup: #{backup_path}"

ContactsDB.with_db do |db|
  before = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'iglakovo'").to_i

  db.execute('BEGIN')
  db.execute(<<~SQL)
    UPDATE contacts
       SET address = CASE
                       WHEN TRIM(COALESCE(address, '')) = '' THEN name
                       ELSE address
                     END,
           name = CASE
                    WHEN TRIM(COALESCE(consumer, '')) <> '' THEN consumer
                    ELSE name
                  END
     WHERE category = 'iglakovo'
  SQL
  db.execute('COMMIT')

  sample = db.execute(<<~SQL)
    SELECT id, name, address, phone
      FROM contacts
     WHERE category = 'iglakovo'
     ORDER BY id
     LIMIT 5
  SQL

  puts "Updated rows: #{before}"
  sample.each do |row|
    puts [row['id'], row['name'], row['address'], row['phone']].map { |v| v.to_s.gsub(/\s+/, ' ') }.join(' | ')
  end
rescue StandardError
  db.execute('ROLLBACK') rescue nil
  raise
end
