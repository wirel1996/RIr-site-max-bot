# frozen_string_literal: true

require 'roo'
require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'
require_relative '../storage/water_registry_db'

module PhysContactsImportService
  module_function

  CATEGORY = 'phys'
  HEADER_HINTS = %w[идентификатор потребит адрес телефон руковод ответствен почт].freeze

  def parse_file(path)
    book = Roo::Spreadsheet.open(path)
    sheet = book.sheet(0)
    last_row = sheet.last_row.to_i
    return [] if last_row < 2

    header_row, header_idx = find_header_row(sheet, last_row)
    return [] unless header_row

    column_map = build_column_map(header_row)
    rows = []
    ((header_idx + 1)..last_row).each do |i|
      cells = safe_row(sheet, i)
      next if cells.all? { |c| c.to_s.strip.empty? }

      built = build_row(cells, column_map, i)
      rows << built if built
    end
    rows
  end

  def run(path:, dry_run: false)
    rows = parse_file(path)
    stats = {
      parsed: rows.size,
      purged: nil,
      imported: 0,
      skipped: 0,
      warnings: [],
      unlinked_uute: 0,
      unlinked_water: 0
    }

    return stats.merge(dry_run: true, would_import: rows.size) if dry_run

    ContactsDB.with_db do |db|
      db.execute('BEGIN')
      begin
        stats[:purged] = purge_phys!(db)
        import_stats = import!(db, rows)
        stats.merge!(import_stats)
        ContactsDB.set_meta(db, 'last_phys_contacts_import_at', Time.now.to_i.to_s)
        db.execute('COMMIT')
      rescue StandardError => e
        db.execute('ROLLBACK') rescue nil
        raise e
      end
    end
    stats
  end

  def purge_phys!(db)
    object_ids = db.execute(
      "SELECT DISTINCT object_id FROM contacts WHERE category = ? AND object_id IS NOT NULL AND object_id > 0",
      [CATEGORY]
    ).map { |row| row['object_id'].to_i }.uniq

    contacts_count = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = ?", [CATEGORY]).to_i
    db.execute('DELETE FROM contacts WHERE category = ?', [CATEGORY])

    unlinked = unlink_related_objects!(object_ids)

    events_deleted = 0
    objects_deleted = 0
    unless object_ids.empty?
      placeholders = (['?'] * object_ids.size).join(', ')
      events_deleted = db.get_first_value(
        "SELECT COUNT(*) FROM object_switch_events WHERE object_id IN (#{placeholders})",
        object_ids
      ).to_i
      db.execute("DELETE FROM object_switch_events WHERE object_id IN (#{placeholders})", object_ids)

      objects_deleted = db.get_first_value(
        "SELECT COUNT(*) FROM registry_objects WHERE id IN (#{placeholders})",
        object_ids
      ).to_i
      db.execute("DELETE FROM registry_objects WHERE id IN (#{placeholders})", object_ids)
    end

    {
      contacts: contacts_count,
      objects: objects_deleted,
      switch_events: events_deleted,
      unlinked_uute: unlinked[:uute],
      unlinked_water: unlinked[:water]
    }
  end

  def import!(db, rows)
    imported = 0
    skipped = 0
    warnings = []
    seen_identifiers = {}
    now = Time.now.to_i

    rows.each do |row|
      object_attrs = row[:object]
      contact_attrs = row[:contact]
      identifier = object_attrs[:identifier].to_s.strip

      if identifier.empty? && [object_attrs[:name], object_attrs[:address]].all? { |v| v.to_s.strip.empty? }
        skipped += 1
        next
      end

      if !identifier.empty?
        if seen_identifiers[identifier.downcase]
          warnings << "Строка #{contact_attrs[:source_row]}: дубликат UID #{identifier}, пропуск"
          skipped += 1
          next
        end
        seen_identifiers[identifier.downcase] = true
      end

      object_id = ContactsDB.upsert_registry_object(
        db,
        name: object_attrs[:name],
        address: object_attrs[:address],
        identifier: identifier,
        source: 'phys_import'
      )

      db.execute(
        <<~SQL,
          INSERT INTO contacts
            (category, name, connection_point, consumer, manager, address, phone, phone_alt, email, postal_address, notes, identifier, metering_presence, disconnected, disconnected_date, object_id, source_row, updated_at)
          VALUES (?, NULL, NULL, ?, ?, NULL, ?, ?, ?, ?, ?, NULL, ?, 'нет', NULL, ?, ?, ?)
        SQL
        [
          CATEGORY,
          contact_attrs[:consumer],
          contact_attrs[:manager],
          contact_attrs[:phone],
          contact_attrs[:phone_alt],
          contact_attrs[:email],
          contact_attrs[:postal_address],
          contact_attrs[:notes],
          contact_attrs[:metering_presence],
          object_id,
          contact_attrs[:source_row],
          now
        ]
      )
      imported += 1
    end

    { imported: imported, skipped: skipped, warnings: warnings }
  end

  def build_row(cells, column_map, source_row)
    identifier = column_value(cells, column_map, 'идентификатор')
    consumer = column_value(cells, column_map, 'наименование потребит', 'потребит')
    metering_presence = column_value(cells, column_map, 'наличие пу', 'наличие')
    address = column_value(cells, column_map, 'адрес')
    manager = column_value(cells, column_map, 'руковод')
    responsible = column_value(cells, column_map, 'ответствен')
    phone_raw = column_value(cells, column_map, 'телефон')
    phone_alt_raw = column_value_fuzzy(cells, column_map, 'альтернатив')
    email = column_value_fuzzy(cells, column_map, 'электрон', 'email')
    postal_address = column_value_fuzzy(cells, column_map, 'почтов')

    notes = responsible
    extra_phones = []
    if phone_like_text?(responsible)
      extra_phones << responsible
      notes = ''
    end

    phones = split_phones(phone_raw, phone_alt_raw, *extra_phones)
    phone = phones[0] || ''
    phone_alt = phones.drop(1).join('; ')

    return nil if [identifier, consumer, address, manager, phone, phone_alt, email, postal_address, notes, metering_presence].all?(&:empty?)

    {
      object: {
        identifier: identifier,
        name: consumer,
        address: address
      },
      contact: {
        consumer: consumer,
        manager: manager,
        phone: phone,
        phone_alt: phone_alt,
        email: email,
        postal_address: postal_address,
        notes: notes,
        metering_presence: metering_presence,
        source_row: source_row
      }
    }
  end

  def unlink_related_objects!(object_ids)
    return { uute: 0, water: 0 } if object_ids.empty?

    placeholders = (['?'] * object_ids.size).join(', ')
    now = Time.now.to_i

    uute_count = UuteDB.with_db do |db|
      count = db.get_first_value(
        "SELECT COUNT(*) FROM uute_objects WHERE object_id IN (#{placeholders})",
        object_ids
      ).to_i
      db.execute(
        "UPDATE uute_objects SET object_id = NULL, updated_at = ? WHERE object_id IN (#{placeholders})",
        [now] + object_ids
      )
      count
    end

    water_count = WaterRegistryDB.with_db do |db|
      count = db.get_first_value(
        "SELECT COUNT(*) FROM water_registry_rows WHERE object_id IN (#{placeholders})",
        object_ids
      ).to_i
      db.execute(
        "UPDATE water_registry_rows SET object_id = NULL, updated_at = ? WHERE object_id IN (#{placeholders})",
        [now] + object_ids
      )
      count
    end

    { uute: uute_count, water: water_count }
  end

  def find_header_row(sheet, last_row)
    (1..[last_row, 6].min).each do |i|
      cells = safe_row(sheet, i).map { |c| c.to_s.downcase }
      hits = HEADER_HINTS.count { |hint| cells.any? { |c| c.include?(hint) } }
      return [safe_row(sheet, i), i] if hits >= 2
    end
    nil
  end
  private_class_method :find_header_row

  def build_column_map(header_row)
    map = {}
    header_row.each_with_index do |cell, idx|
      key = normalize_header(cell)
      next if key.empty?

      map[key] ||= idx
    end
    map
  end
  private_class_method :build_column_map

  def normalize_header(text)
    text.to_s.downcase.gsub(/[^[:alnum:]]+/u, ' ').strip
  end
  private_class_method :normalize_header

  def safe_row(sheet, idx)
    sheet.row(idx).map { |c| normalize_cell(c) }
  rescue StandardError
    []
  end
  private_class_method :safe_row

  def normalize_cell(value)
    case value
    when nil then ''
    when Numeric
      value.is_a?(Float) && value == value.to_i ? value.to_i.to_s : value.to_s
    when Date, DateTime, Time
      value.strftime('%d.%m.%Y')
    else
      value.to_s.strip
    end
  end
  private_class_method :normalize_cell

  def column_value(cells, column_map, *header_keys)
    header_keys.each do |raw|
      key = normalize_header(raw)
      idx = column_map[key]
      if idx
        val = cells[idx].to_s.strip
        return val unless val.empty?
      end

      column_map.each do |header, col_idx|
        next unless header.include?(key)

        val = cells[col_idx].to_s.strip
        return val unless val.empty?
      end
    end
    ''
  end
  private_class_method :column_value

  def column_value_fuzzy(cells, column_map, *substrings)
    substrings.each do |needle|
      n = needle.to_s.downcase
      column_map.each do |header, idx|
        next unless header.include?(n)

        val = cells[idx].to_s.strip
        return val unless val.empty?
      end
    end
    ''
  end
  private_class_method :column_value_fuzzy

  def phone_like_text?(text)
    s = text.to_s.strip
    return false if s.empty?

    digits = s.gsub(/\D/, '')
    return false if digits.length < 7

    s.gsub(/[\d\s\-()+;,]/, '').strip.empty?
  end
  private_class_method :phone_like_text?

  def split_phones(*values)
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
  end
  private_class_method :split_phones

  def clean_phone(value)
    value.to_s
          .gsub(/<[^>]*>/, ' ')
          .gsub(/\b(?:тел|т|сот)\.?\s*/i, '')
          .gsub(/&nbsp;/i, ' ')
          .gsub(/\s+/, ' ')
          .strip
  end
  private_class_method :clean_phone

  def phone_key(value)
    digits = value.to_s.gsub(/\D+/, '')
    return '' if digits.empty?
    return digits[-10, 10] if digits.length == 11 && %w[7 8].include?(digits[0])
    return digits if digits.length == 10 && digits.start_with?('9')

    digits
  end
  private_class_method :phone_key
end
