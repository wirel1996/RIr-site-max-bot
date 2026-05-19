# frozen_string_literal: true

require 'fileutils'
require_relative '../storage/contacts_db'

def clean_phone_text(value)
  s = value.to_s
  return '' if s.strip.empty?

  s = s.gsub(/<[^>]*>/, ' ')
  s = s.gsub(/&nbsp;/i, ' ')
       .gsub(/&amp;/i, '&')
       .gsub(/&quot;/i, '"')
       .gsub(/&#39;|&apos;/i, "'")
  s.gsub(/\s+/, ' ').strip
end

db_path = ContactsDB.db_path
backup_path = "#{db_path}.bak-phone-html-#{Time.now.strftime('%Y%m%d%H%M%S')}"
FileUtils.cp(db_path, backup_path)
puts "Backup: #{backup_path}"

updated = 0

ContactsDB.with_db do |db|
  rows = db.execute(<<~SQL)
    SELECT id, phone, phone_alt
      FROM contacts
     WHERE phone LIKE '%<%'
        OR phone_alt LIKE '%<%'
        OR phone LIKE '%&nbsp;%'
        OR phone_alt LIKE '%&nbsp;%'
  SQL

  db.execute('BEGIN')
  rows.each do |row|
    db.execute(
      'UPDATE contacts SET phone = ?, phone_alt = ?, updated_at = ? WHERE id = ?',
      [
        clean_phone_text(row['phone']).empty? ? nil : clean_phone_text(row['phone']),
        clean_phone_text(row['phone_alt']).empty? ? nil : clean_phone_text(row['phone_alt']),
        Time.now.to_i,
        row['id']
      ]
    )
    updated += 1
  end
  db.execute('COMMIT')

  puts "Updated rows: #{updated}"
rescue StandardError
  db.execute('ROLLBACK') rescue nil
  raise
end
