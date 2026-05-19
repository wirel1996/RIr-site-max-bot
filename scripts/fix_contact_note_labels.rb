# frozen_string_literal: true
require_relative '../storage/contacts_db'

LABELS_BY_CATEGORY = {
  'phys' => ['Ответственные лица:', 'Почтовый адрес:'],
  'legal' => ['Ответственные лица:', 'Почтовый адрес:'],
  'budget' => ['Ответственные лица:', 'Почтовый адрес:'],
  'embedded' => ['Ответственные лица:', 'Обслуживающая организация:', 'Почтовый адрес:'],
  'iglakovo' => ['Ответственные лица:', 'Почтовый адрес:']
}.freeze

changed = 0
ContactsDB.with_db do |db|
  db.execute("SELECT id, category, notes FROM contacts WHERE notes IS NOT NULL AND notes <> ''").each do |row|
    labels = LABELS_BY_CATEGORY[row['category'].to_s] || ['Ответственные лица:', 'Почтовый адрес:']
    bad_index = 0
    lines = row['notes'].to_s.split("\n", -1).map do |line|
      if line.match?(/\A\?+\s+\?+:/)
        label = labels[bad_index] || labels.last
        bad_index += 1
        line.sub(/\A\?+\s+\?+:/, label)
      else
        line
      end
    end
    fixed = lines.join("\n")
    next if fixed == row['notes'].to_s

    db.execute('UPDATE contacts SET notes = ?, updated_at = ? WHERE id = ?', [fixed, Time.now.to_i, row['id']])
    changed += 1
  end
end

puts "fixed_notes=#{changed}"
