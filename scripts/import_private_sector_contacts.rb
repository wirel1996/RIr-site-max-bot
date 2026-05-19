# frozen_string_literal: true

require 'roo'
require_relative '../storage/contacts_db'

path = ARGV[0] || 'C:/Users/Администратор/Desktop/Основной файл ОКЭ ( Прочие  ГСПО) 2026 год.xlsx'
sheet = Roo::Spreadsheet.open(path).sheet(5)

def cell(sheet, row, col)
  value = sheet.cell(row, col)
  case value
  when Date, DateTime, Time
    value.strftime('%d.%m.%Y')
  when Float
    value % 1 == 0 ? value.to_i.to_s : value.to_s
  else
    value.to_s.strip
  end
end

def norm(value)
  value.to_s.downcase.tr('ё', 'е').gsub(/[«»"№.,()\/\\_-]+/, ' ').gsub(/\s+/, ' ').strip
end

def norm_address(value)
  norm(value)
    .gsub(/\bул\b|\bулица\b|\bг\b|\bсеверск\b|\bмик н\b|\bмик он\b|\bмикрорайон\b/, ' ')
    .gsub(/\bбр\b/, 'братьев')
    .gsub(/\s+/, ' ')
    .strip
end

def uuid?(value)
  value.to_s.strip.match?(/\A[0-9a-f-]{36}\z/i)
end

def clean_phone(value)
  value.to_s
    .gsub(/<[^>]*>/, ' ')
    .gsub(/\b(?:тел|т)\.?\s*/i, '')
    .gsub(/&nbsp;/i, ' ')
    .gsub(/&amp;/i, '&')
    .gsub(/&quot;/i, '"')
    .gsub(/&#39;|&apos;/i, "'")
    .gsub(/\s+/, ' ')
    .strip
end

def phone_key(value)
  digits = value.to_s.gsub(/\D+/, '')
  return '' if digits.empty?
  return digits[-10, 10] if digits.length == 11 && ['7', '8'].include?(digits[0])
  return digits if digits.length == 10 && digits.start_with?('9')

  digits
end

def merge_phones(*values)
  seen_keys = []
  values.flat_map { |value| clean_phone(value).split(/\s*(?:;|,|\n)\s*/) }
        .map(&:strip)
        .reject(&:empty?)
        .each_with_object([]) do |phone, phones|
          key = phone_key(phone)
          next if key.empty?
          next if seen_keys.any? { |seen| seen == key || (seen.length >= 7 && key.length >= 7 && (seen.include?(key) || key.include?(seen))) }

          seen_keys << key
          phones << phone
        end
        .join('; ')
end

def build_attrs(sheet, row)
  kind = norm(cell(sheet, row, 2))
  identifier = cell(sheet, row, 7)
  return nil unless ['иглаково', 'частный дом'].include?(kind) || uuid?(identifier)

  name = cell(sheet, row, 4)
  manager = cell(sheet, row, 5)
  address = cell(sheet, row, 6)
  responsible = cell(sheet, row, 8)
  service_org = cell(sheet, row, 9)
  postal_address = cell(sheet, row, 10)
  email = cell(sheet, row, 11)
  phone = merge_phones(cell(sheet, row, 12), cell(sheet, row, 13))
  fax = cell(sheet, row, 14)

  notes = []
  notes << "Почтовый адрес: #{postal_address}" unless postal_address.empty?
  notes << "Ответственные лица: #{responsible}" unless responsible.empty?
  notes << "Обслуживающая организация: #{service_org}" unless service_org.empty?
  notes << "Факс: #{fax}" unless fax.empty?

  attrs = {
    'category' => 'iglakovo',
    'name' => name,
    'connection_point' => nil,
    'consumer' => nil,
    'manager' => manager == name ? nil : manager,
    'address' => address,
    'phone' => phone,
    'phone_alt' => nil,
    'email' => email,
    'notes' => notes.join("\n"),
    'identifier' => identifier,
    'source_row' => row
  }

  return nil if [attrs['name'], attrs['address'], attrs['identifier']].all? { |value| value.to_s.strip.empty? }

  attrs
end

def find_existing(db, attrs)
  identifier = attrs['identifier'].to_s.strip
  unless identifier.empty?
    row = db.get_first_row(
      "SELECT * FROM contacts WHERE category = 'iglakovo' AND identifier = ? ORDER BY id LIMIT 1",
      [identifier]
    )
    return [row, 'identifier'] if row
  end

  address_key = norm_address(attrs['address'])
  unless address_key.empty?
    db.execute(
      "SELECT * FROM contacts WHERE category = 'iglakovo' AND address IS NOT NULL ORDER BY id"
    ).each do |row|
      next unless norm_address(row['address']) == address_key
      row_identifier = row['identifier'].to_s.strip
      next unless row_identifier.empty? || identifier.empty? || row_identifier == identifier

      return [row, 'address']
    end
  end

  title = norm(attrs['name'])
  return [nil, nil] if title.empty?

  row = db.get_first_row(
    "SELECT * FROM contacts WHERE category = 'iglakovo' AND lower_ru(coalesce(name, '')) = ? ORDER BY id LIMIT 1",
    [attrs['name'].to_s.downcase]
  )
  if row
    row_identifier = row['identifier'].to_s.strip
    row = nil unless row_identifier.empty? || identifier.empty? || row_identifier == identifier
  end
  [row, row ? 'name' : nil]
end

added = 0
updated = Hash.new(0)
skipped = 0
seen = 0
now = Time.now.to_i

ContactsDB.with_db do |db|
  db.execute('BEGIN')
  begin
    (2..sheet.last_row.to_i).each do |row|
      attrs = build_attrs(sheet, row)
      unless attrs
        skipped += 1
        next
      end
      seen += 1

      existing, matched_by = find_existing(db, attrs)
      values = attrs.merge('updated_at' => now)
      if existing
        assignments = values.keys.reject { |key| key == 'category' }.map { |key| "#{key} = ?" }.join(', ')
        params = values.reject { |key, _| key == 'category' }.values + [existing['id']]
        db.execute("UPDATE contacts SET #{assignments} WHERE id = ?", params)
        updated[matched_by] += 1
      else
        keys = values.keys
        placeholders = (['?'] * keys.size).join(', ')
        db.execute("INSERT INTO contacts (#{keys.join(', ')}) VALUES (#{placeholders})", values.values)
        added += 1
      end
    end
    ContactsDB.set_meta(db, 'last_private_sector_contacts_import_at', now)
    db.execute('COMMIT')
  rescue StandardError => e
    db.execute('ROLLBACK') rescue nil
    raise e
  end
end

puts({ seen: seen, added: added, updated: updated, skipped: skipped }.inspect)
