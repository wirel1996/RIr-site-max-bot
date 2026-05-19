# frozen_string_literal: true

require 'fileutils'
require_relative '../storage/contacts_db'

def normalize_phone_key(value)
  digits = value.to_s.gsub(/\D+/, '')
  digits = "7#{digits[1..]}" if digits.length == 11 && digits.start_with?('8')
  digits
end

def merge_phone_values(*values)
  seen = {}
  parts = []

  values.each do |value|
    value.to_s.split(%r{[,;/\n]+}).each do |raw_part|
      part = raw_part.strip
      next if part.empty?

      key = normalize_phone_key(part)
      key = part.downcase if key.empty?
      next if seen[key]

      seen[key] = true
      parts << part
    end
  end

  parts.join(', ')
end

db_path = ContactsDB.db_path
backup_path = "#{db_path}.bak-iglakovo-phones-#{Time.now.strftime('%Y%m%d%H%M%S')}"
FileUtils.cp(db_path, backup_path)
puts "Backup: #{backup_path}"

updated = 0

ContactsDB.with_db do |db|
  rows = db.execute(<<~SQL)
    SELECT id, phone, phone_alt
      FROM contacts
     WHERE category = 'iglakovo'
       AND TRIM(COALESCE(phone_alt, '')) <> ''
  SQL

  db.execute('BEGIN')
  rows.each do |row|
    merged = merge_phone_values(row['phone'], row['phone_alt'])
    db.execute(
      'UPDATE contacts SET phone = ?, phone_alt = NULL, updated_at = ? WHERE id = ?',
      [merged.empty? ? nil : merged, Time.now.to_i, row['id']]
    )
    updated += 1
  end
  db.execute('COMMIT')

  sample = db.execute(<<~SQL)
    SELECT id, name, address, phone, phone_alt
      FROM contacts
     WHERE category = 'iglakovo'
     ORDER BY id
     LIMIT 8
  SQL

  puts "Updated rows: #{updated}"
  sample.each do |row|
    puts [row['id'], row['name'], row['address'], row['phone'], row['phone_alt']].map { |v| v.to_s.gsub(/\s+/, ' ') }.join(' | ')
  end
rescue StandardError
  db.execute('ROLLBACK') rescue nil
  raise
end
