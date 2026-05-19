# frozen_string_literal: true

require 'fileutils'
require_relative '../storage/contacts_db'

backup = "#{ContactsDB.db_path}.bak-before-postal-address-#{Time.now.strftime('%Y%m%d_%H%M%S')}"
FileUtils.cp(ContactsDB.db_path, backup) if File.exist?(ContactsDB.db_path)

postal_label = "Почтовый адрес"
responsible_label = "Ответственные лица"
updated = 0

ContactsDB.with_db do |db|
  db.execute('BEGIN')
  begin
    db.execute("SELECT id, notes, postal_address FROM contacts WHERE COALESCE(notes, '') <> ''").each do |row|
      notes = row['notes'].to_s
      postal = row['postal_address'].to_s.strip
      lines = notes.split(/\r?\n/).map(&:strip).reject(&:empty?)
      next if lines.empty?

      postal_parts = []
      remaining = []
      lines.each do |line|
        if line.match?(/\A#{Regexp.escape(postal_label)}\s*:/i)
          value = line.sub(/\A#{Regexp.escape(postal_label)}\s*:\s*/i, '').strip
          postal_parts << value unless value.empty?
        elsif line.match?(/\A\?{4,}\s+\?{4,}\s*:/)
          value = line.sub(/\A\?{4,}\s+\?{4,}\s*:\s*/, '').strip
          postal_parts << value unless value.empty?
        else
          remaining << line
        end
      end
      next if postal_parts.empty?

      next_postal = postal.empty? ? postal_parts.join("\n") : postal
      next_notes = remaining.map do |line|
        line.sub(/\A#{Regexp.escape(responsible_label)}\s*:\s*/i, '').strip
      end.reject(&:empty?).join("\n")

      db.execute(
        'UPDATE contacts SET postal_address = ?, notes = ?, updated_at = ? WHERE id = ?',
        [next_postal.empty? ? nil : next_postal, next_notes.empty? ? nil : next_notes, Time.now.to_i, row['id'].to_i]
      )
      updated += 1
    end
    db.execute('COMMIT')
  rescue StandardError => e
    db.execute('ROLLBACK') rescue nil
    raise e
  end
end

puts "backup=#{backup}"
puts "updated=#{updated}"
