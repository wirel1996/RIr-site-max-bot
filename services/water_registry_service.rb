# frozen_string_literal: true

require 'json'
require 'date'
require 'roo'
require 'securerandom'

require_relative '../storage/water_registry_db'
require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'

module WaterRegistryService
  module_function

  PAGE_SIZE = 80
  XLSX_COLUMNS = {
    'point_number' => 1,
    'identifier' => 2,
    'actual_connection_point' => 3,
    'connected' => 4,
    'point_filter' => 5,
    'gspo_count_in_point' => 6,
    'gspo_name' => 7,
    'standalone_address' => 8,
    'leader_name' => 9,
    'phone' => 10,
    'metering_presence' => 11,
    'application' => 12,
    'no_debt' => 13,
    'power_of_attorney' => 14,
    'contract' => 15,
    'uute' => 16,
    'third_party_disconnection' => 17,
    'payment' => 18,
    'verdict' => 19,
    'note' => 20,
    'all_except_payment' => 21,
    'tf_in_ts' => 22,
    'connection_act' => 23,
    'illegal_connection_2025' => 24,
    'illegal_connection_2026' => 25
  }.freeze
  DISCONNECT_SHEET = 'БУ-1'
  DISCONNECT_KIND_HEADER = 'назначение'
  DISCONNECT_NAME_HEADER = 'Наименование потребителей'
  DISCONNECT_IDENTIFIER_HEADER = 'Идентификатор'
  DISCONNECT_NOTE_HEADER = 'Акт отключения 2026г'

  FORMULA_INPUTS = %w[
    application no_debt power_of_attorney contract uute uute_verified third_party_disconnection payment
  ].freeze

  def enabled?
    WaterRegistryDB.with_db { |db| db.get_first_row('SELECT 1 FROM water_registry_rows LIMIT 1') }
    true
  rescue StandardError
    false
  end

  def list(page:, query: nil, point: nil, sort: nil, dir: nil, payment_from: nil, payment_to: nil, application_from: nil, application_to: nil)
    offset = page.to_i * PAGE_SIZE
    q = query.to_s.strip
    p = point.to_s.strip
    s = sort.to_s.strip
    d = dir.to_s.downcase == 'desc' ? 'desc' : 'asc'
    from = iso_date(payment_from)
    to = iso_date(payment_to)
    app_from = iso_date(application_from)
    app_to = iso_date(application_to)
    WaterRegistryDB.with_db do |db|
      total = WaterRegistryDB.count(
        db, query: q, point: p,
        payment_from: from, payment_to: to,
        application_from: app_from, application_to: app_to
      )
      records = WaterRegistryDB.list(
        db, limit: PAGE_SIZE, offset: offset, query: q, point: p, sort: s, dir: d,
        payment_from: from, payment_to: to,
        application_from: app_from, application_to: app_to
      ).map { |row| public_row(row) }
      {
        page: page.to_i,
        page_size: PAGE_SIZE,
        total: total,
        query: q,
        point: p,
        payment_from: from,
        payment_to: to,
        application_from: app_from,
        application_to: app_to,
        sort: s,
        dir: d,
        records: records,
        last_import: WaterRegistryDB.last_import(db)
      }
    end
  end

  def paid_rows(payment_from: nil, payment_to: nil)
    from = iso_date(payment_from) || Date.today.iso8601
    to = iso_date(payment_to) || from
    WaterRegistryDB.with_db do |db|
      {
        payment_from: from,
        payment_to: to,
        records: WaterRegistryDB.paid_between(db, payment_from: from, payment_to: to).map { |row| public_row(row) }
      }
    end
  end

  def find(id)
    WaterRegistryDB.with_db do |db|
      row = WaterRegistryDB.find(db, id)
      row && public_row(row, detail: true)
    end
  end

  def rows_for_contact(contact_id)
    WaterRegistryDB.with_db do |db|
      rows = WaterRegistryDB.rows_for_contact(db, contact_id)
      { records: rows.map { |row| public_row(row) } }
    end
  end

  def normalize_existing!
    WaterRegistryDB.with_db { |db| WaterRegistryDB.normalize_metering_flags(db) }
    WaterRegistryDB.with_db { |db| WaterRegistryDB.normalize_water_supplied_flags(db) }
    { ok: true }
  end

  def disconnected_points
    WaterRegistryDB.with_db do |db|
      points = WaterRegistryDB.disconnected_points(db)
      { points: points, total: points.size }
    end
  end

  def disconnected_points_export
    WaterRegistryDB.with_db do |db|
      points = WaterRegistryDB.disconnected_points(db)
      points.map { |p| { point: p } }
    end
  end

  def create(attrs)
    values = attrs.each_with_object({}) do |(key, value), memo|
      k = key.to_s
      next unless WaterRegistryDB.editable_fields.include?(k)

      memo[k] = value.to_s.strip
    end
    hydrate_from_contact!(values)
    if values.values_at('actual_connection_point', 'point_number', 'gspo_name', 'standalone_address').all? { |value| value.to_s.strip.empty? }
      raise ArgumentError, 'Заполните хотя бы точку, название или адрес'
    end

    values['source_key'] = "manual:#{Time.now.to_i}:#{SecureRandom.hex(4)}"
    values['source_row'] = nil
    values['raw_json'] = JSON.generate('manual' => true)
    values['point_number'] = point_group(values['actual_connection_point']) if values['point_number'].to_s.strip.empty?
    values.merge!(manual_metering_values(values))
    values.merge!(calculated_fields(values))
    unless metering_absent?(values)
      values.merge!(uute_link_fields(values))
    end
    row = WaterRegistryDB.with_db { |db| WaterRegistryDB.create(db, values) }
    sync_metering_presence_from_water!

    if values['water_supplied'].to_s.strip.downcase == 'да'
      point = values['actual_connection_point'].to_s.strip
      if !point.empty?
        WaterRegistryDB.with_db { |db| WaterRegistryDB.cascade_water_supplied(db, point, 'да') }
      end
    end

    public_row(row, detail: true)
  end

  def update(id, attrs)
    existing = WaterRegistryDB.with_db { |db| WaterRegistryDB.find(db, id) }
    raise ArgumentError, 'water registry row not found' unless existing

    values = attrs.each_with_object({}) do |(key, value), memo|
      k = key.to_s
      next unless WaterRegistryDB.editable_fields.include?(k)

      memo[k] = value.to_s.strip
    end
    return find(id) if values.empty?

    explicit_keys = values.keys
    merged = existing.merge(values)
    values.merge!(normalized_metering_values(merged))
    merged = existing.merge(values)
    calculated = calculated_fields(merged)
    calculated.each do |key, value|
      values[key] = value unless explicit_keys.include?(key)
    end
    if values.key?('uute_id') && !metering_absent?(merged)
      manual_uute = manual_uute_fields(values['uute_id'])
      values.merge!(manual_uute)
      calculated_fields(existing.merge(values)).each do |key, value|
        values[key] = value unless explicit_keys.include?(key)
      end
    end
    if values.key?('contact_id')
      values.merge!(manual_contact_fields(values['contact_id'], existing.merge(values)))
      merged = existing.merge(values)
    end
    unless metering_absent?(merged) || values.key?('uute_verification_until')
      values.merge!(uute_link_fields(merged.merge(calculated)))
    end

    WaterRegistryDB.with_db { |db| WaterRegistryDB.update(db, id, values) }
    sync_metering_presence_from_water!

    if values.key?('water_supplied') && values['water_supplied'].to_s.strip.downcase == 'да'
      merged = existing.merge(values)
      point = merged['actual_connection_point'].to_s.strip
      if !point.empty?
        WaterRegistryDB.with_db { |db| WaterRegistryDB.cascade_water_supplied(db, point, 'да') }
      end
    end

    find(id)
  end

  def import_file(path, filename: nil)
    book = Roo::Spreadsheet.open(path)
    sheet = book.sheet(0)
    raise ArgumentError, 'лист с реестром не найден' unless sheet

    added = 0
    updated = 0
    skipped = 0
    total = 0

    WaterRegistryDB.with_db do |db|
      db.execute('BEGIN')
      begin
        (2..sheet.last_row).each do |row_index|
          total += 1
          attrs = attrs_from_row(sheet, row_index)
          if attrs.nil?
            skipped += 1
            next
          end
          preserve_manual_links!(db, attrs)

          result = WaterRegistryDB.upsert_row(db, attrs)
          result == :added ? added += 1 : updated += 1
        end
        WaterRegistryDB.record_import(db, filename: filename || File.basename(path), added: added, updated: updated, skipped: skipped, total: total)
        db.execute('COMMIT')
      rescue StandardError => e
        db.execute('ROLLBACK') rescue nil
        raise e
      end
    end

    sync_metering_presence_from_water!
    { added: added, updated: updated, skipped: skipped, total: total }
  end

  def sync_verification_from_uute!(uute_id)
    id = uute_id.to_i
    return 0 if id <= 0

    uute = UuteDB.with_db { |db| UuteDB.find(db, id) }
    return 0 unless uute

    verification = uute['nearest_verification_date'].to_s
    not_absent = "lower_ru(COALESCE(metering_presence, '')) <> 'нет' AND lower_ru(COALESCE(uute, '')) <> 'нет'"
    contact_ids = UuteDB.with_db do |udb|
      UuteDB.links_for_uute(udb, id).map { |link| link['contact_id'].to_i }.select(&:positive?).uniq
    end
    updated = 0

    WaterRegistryDB.with_db do |db|
      now = Time.now.to_i
      db.execute(
        "UPDATE water_registry_rows SET uute_verification_until = ?, updated_at = ? WHERE uute_id = ? AND #{not_absent}",
        [verification, now, id]
      )
      updated += db.changes

      contact_ids.each do |contact_id|
        selected = selected_uute_for_contact(contact_id)
        next unless selected && selected[:uute_id] == id

        db.execute(
          "UPDATE water_registry_rows SET uute_id = ?, uute_verification_until = ?, updated_at = ? WHERE contact_id = ? AND #{not_absent}",
          [id, verification, now, contact_id]
        )
        updated += db.changes
      end
    end

    updated
  end

  def sync_metering_presence_from_water!
    contacts_by_identifier = ContactsDB.with_db do |db|
      db.execute("SELECT id, identifier FROM contacts WHERE COALESCE(identifier, '') <> ''").to_h do |row|
        [row['identifier'].to_s.strip.downcase, row['id'].to_i]
      end
    end
    current_contact_ids = ContactsDB.with_db do |db|
      db.execute('SELECT id FROM contacts').map { |row| row['id'].to_i }.to_h { |id| [id, true] }
    end

    values_by_contact_id = {}
    WaterRegistryDB.with_db do |db|
      db.execute("SELECT id, contact_id, identifier, metering_presence, uute FROM water_registry_rows").each do |row|
        contact_id = contacts_by_identifier[row['identifier'].to_s.strip.downcase] || row['contact_id'].to_i
        next unless contact_id.positive? && current_contact_ids[contact_id]

        db.execute('UPDATE water_registry_rows SET contact_id = ?, updated_at = ? WHERE id = ?', [contact_id, Time.now.to_i, row['id']]) if row['contact_id'].to_i != contact_id

        value = row['metering_presence'].to_s.strip
        value = row['uute'].to_s.strip if value.empty?
        next if value.empty?

        existing = values_by_contact_id[contact_id].to_s
        values_by_contact_id[contact_id] = value if existing.empty? || normalize_text(value) == 'нет'

        if normalize_text(value) == 'нет'
          db.execute('UPDATE water_registry_rows SET uute_id = NULL, uute_verification_until = ?, uute_match_note = ?, updated_at = ? WHERE id = ?', ['', '', Time.now.to_i, row['id']])
        end
      end
    end

    ContactsDB.with_db do |db|
      values_by_contact_id.each do |contact_id, value|
        ContactsDB.update_metering_presence(db, contact_id, value)
      end
    end

    { updated: values_by_contact_id.size }
  end

  def hydrate_from_contact!(values)
    contact_id = values['contact_id'].to_i
    return values unless contact_id.positive?

    contact = ContactsDB.with_db { |db| ContactsDB.find_by_id(db, contact_id) }
    raise ArgumentError, 'contact not found' unless contact

    values['identifier'] = contact['identifier'].to_s.strip if values['identifier'].to_s.strip.empty?
    values['gspo_name'] = contact_name_for_water(contact) if values['gspo_name'].to_s.strip.empty?
    values['standalone_address'] = contact['address'].to_s.strip if values['standalone_address'].to_s.strip.empty?
    values['leader_name'] = contact_person_for_water(contact) if values['leader_name'].to_s.strip.empty?
    values['phone'] = contact['phone'].to_s.strip if values['phone'].to_s.strip.empty?
    values['actual_connection_point'] = contact['connection_point'].to_s.strip if values['actual_connection_point'].to_s.strip.empty?
    values['metering_presence'] = contact['metering_presence'].to_s.strip if values['metering_presence'].to_s.strip.empty?
    values
  end
  private_class_method :hydrate_from_contact!

  def contact_name_for_water(contact)
    [contact['name'], contact['consumer'], contact['manager']]
      .map { |value| value.to_s.strip }
      .find { |value| !value.empty? }
      .to_s
  end
  private_class_method :contact_name_for_water

  def contact_person_for_water(contact)
    [contact['consumer'], contact['manager']]
      .map { |value| value.to_s.strip }
      .find { |value| !value.empty? }
      .to_s
  end
  private_class_method :contact_person_for_water

  def selected_uute_for_contact(contact_id)
    links = UuteDB.with_db { |db| UuteDB.links_for_contact(db, contact_id) }
    linked = links.filter_map do |link|
      uute = UuteDB.with_db { |db| UuteDB.find(db, link['uute_id']) }
      next unless uute

      { link: link, uute: uute }
    end
    selected = linked.find { |item| !item[:uute]['nearest_verification_date'].to_s.strip.empty? } || linked.first
    return nil unless selected

    {
      uute_id: selected[:uute]['id'].to_i,
      verification_until: selected[:uute]['nearest_verification_date'].to_s,
      note: ['связь контакта с УУТЭ', selected[:link]['match_reason']].compact.reject(&:empty?).join('; ')
    }
  end
  private_class_method :selected_uute_for_contact

  def import_disconnections(path, filename: nil)
    book = Roo::Spreadsheet.open(path)
    sheet_name = book.sheets.include?(DISCONNECT_SHEET) ? DISCONNECT_SHEET : book.sheets.first
    sheet = book.sheet(sheet_name)
    raise ArgumentError, 'лист с отключениями не найден' unless sheet
    columns = header_columns(sheet)
    kind_column = require_header!(columns, DISCONNECT_KIND_HEADER)
    name_column = require_header!(columns, DISCONNECT_NAME_HEADER)
    identifier_column = require_header!(columns, DISCONNECT_IDENTIFIER_HEADER)
    note_column = require_header!(columns, DISCONNECT_NOTE_HEADER)

    disconnected = []
    total = 0
    skipped = 0

    (2..sheet.last_row.to_i).each do |row_index|
      kind = normalize_text(cell_value(sheet.cell(row_index, kind_column)))
      next unless kind == 'гспо'

      total += 1
      note = cell_value(sheet.cell(row_index, note_column))
      if note.empty?
        skipped += 1
        next
      end

      identifier = cell_value(sheet.cell(row_index, identifier_column))
      name = cell_value(sheet.cell(row_index, name_column))
      if identifier.empty? && name.empty?
        skipped += 1
        next
      end

      disconnected << { identifier: identifier, name: name, note: note, source_row: row_index }
    end

    rows = WaterRegistryDB.with_db do |db|
      db.execute('SELECT id, identifier, gspo_name FROM water_registry_rows')
    end
    by_identifier = rows.each_with_object({}) do |row, memo|
      key = row['identifier'].to_s.strip.downcase
      memo[key] = row unless key.empty?
    end
    matched_ids = {}
    unmatched = []

    disconnected.each do |item|
      match = by_identifier[item[:identifier].to_s.strip.downcase]
      unless match
        unmatched << item
        next
      end

      matched_ids[match['id'].to_i] = item[:note]
    end

    WaterRegistryDB.with_db do |db|
      db.execute('BEGIN')
      begin
        now = Time.now.to_i
        previous_disconnection_values = db.execute('SELECT id, third_party_disconnection FROM water_registry_rows').to_h do |row|
          [row['id'].to_i, row['third_party_disconnection'].to_s]
        end
        db.execute("UPDATE water_registry_rows SET third_party_disconnection = 'нет', third_party_disconnection_note = '', updated_at = ?", [now])
        matched_ids.each do |id, note|
          db.execute(
            "UPDATE water_registry_rows SET third_party_disconnection = 'да', third_party_disconnection_note = ?, updated_at = ? WHERE id = ?",
            [note, now, id]
          )
        end
        previous_disconnection_values.each do |id, value|
          db.execute('UPDATE water_registry_rows SET third_party_disconnection = ? WHERE id = ?', [value, id])
        end
        db.execute('SELECT * FROM water_registry_rows').each do |row|
          calculated = calculated_fields(row)
          WaterRegistryDB.update(db, row['id'], calculated)
        end
        db.execute('COMMIT')
      rescue StandardError => e
        db.execute('ROLLBACK') rescue nil
        raise e
      end
    end

    {
      filename: filename || File.basename(path),
      sheet: sheet_name,
      total_gspo_rows: total,
      disconnected_rows: disconnected.size,
      matched: matched_ids.size,
      unmatched: unmatched.size,
      skipped: skipped,
      unmatched_examples: unmatched.first(10)
    }
  end

  def manual_uute_fields(uute_id)
    id = uute_id.to_i
    return { 'uute_id' => nil, 'uute_verification_until' => '', 'uute_match_note' => '' } if id <= 0

    uute = UuteDB.with_db { |db| UuteDB.find(db, id) }
    raise ArgumentError, 'uute not found' unless uute

    {
      'uute_id' => id,
      'uute' => 'да',
      'uute_verification_until' => uute['nearest_verification_date'].to_s,
      'uute_match_note' => 'ручная связь с УУТЭ'
    }
  end
  private_class_method :manual_uute_fields

  def manual_contact_fields(contact_id, existing)
    id = contact_id.to_i
    return { 'contact_id' => nil } if id <= 0

    contact = ContactsDB.with_db { |db| ContactsDB.find_by_id(db, id) }
    raise ArgumentError, 'contact not found' unless contact
    values = {
      'contact_id' => id,
      'uute_match_note' => 'ручная связь с контактом'
    }
    values['identifier'] = contact['identifier'].to_s.strip if existing['identifier'].to_s.strip.empty?
    values['gspo_name'] = contact_name_for_water(contact) if existing['gspo_name'].to_s.strip.empty?
    values['standalone_address'] = contact['address'].to_s.strip if existing['standalone_address'].to_s.strip.empty?
    values['leader_name'] = contact_person_for_water(contact) if existing['leader_name'].to_s.strip.empty?
    values['phone'] = contact['phone'].to_s.strip if existing['phone'].to_s.strip.empty?
    values['actual_connection_point'] = contact['connection_point'].to_s.strip if existing['actual_connection_point'].to_s.strip.empty?
    values['metering_presence'] = contact['metering_presence'].to_s.strip if existing['metering_presence'].to_s.strip.empty?

    uute_link = selected_uute_for_contact(id)
    if uute_link
      values['uute_id'] = uute_link[:uute_id]
      values['uute_verification_until'] = uute_link[:verification_until]
      values['uute_match_note'] = ['ручная связь с контактом', uute_link[:note]].compact.reject(&:empty?).join('; ')
    end
    values
  end
  private_class_method :manual_contact_fields

  def attrs_from_row(sheet, row_index)
    attrs = {}
    XLSX_COLUMNS.each do |key, column|
      attrs[key] = cell_value(sheet.cell(row_index, column))
    end

    return nil if attrs.values_at('point_number', 'gspo_name', 'standalone_address', 'identifier').all? { |value| value.to_s.strip.empty? }

    attrs['source_row'] = row_index
    attrs['source_key'] = source_key(attrs)
    attrs['application_date'] ||= ''
    attrs['third_party_disconnection_note'] = ''
    attrs.merge!(normalized_metering_values(attrs))
    attrs.merge!(calculated_fields(attrs))
    attrs.merge!(uute_link_fields(attrs)) unless metering_absent?(attrs)
    attrs['raw_json'] = JSON.generate(raw_row(sheet, row_index))
    attrs
  end
  private_class_method :attrs_from_row

  def normalized_metering_values(attrs)
    if metering_absent?(attrs)
      {
        'uute' => 'нет',
        'uute_id' => nil,
        'uute_verification_until' => '',
        'uute_match_note' => ''
      }
    else
      { 'uute' => 'да' }
    end
  end
  private_class_method :normalized_metering_values

  def manual_metering_values(attrs)
    return normalized_metering_values(attrs) unless attrs['metering_presence'].to_s.strip.empty?

    {}
  end
  private_class_method :manual_metering_values

  def metering_absent?(attrs)
    normalize_text(attrs['metering_presence']) == 'нет'
  end
  private_class_method :metering_absent?

  def calculated_fields(attrs)
    all_except_payment = all_yes?(attrs, FORMULA_INPUTS - ['payment']) ? 'да' : ''
    verdict = all_yes?(attrs, FORMULA_INPUTS) ? 'да' : ''
    {
      'all_except_payment' => all_except_payment,
      'verdict' => verdict
    }
  end
  private_class_method :calculated_fields

  def split_gspo_names(value)
    value.to_s
      .split(/\s*,\s*|\s*;\s*/)
      .map(&:strip)
      .reject(&:empty?)
  end
  private_class_method :split_gspo_names

  def uute_link_fields(attrs)
    contact_id = attrs['contact_id'].to_i
    match = nil
    if contact_id.positive?
      contact = ContactsDB.with_db { |db| ContactsDB.find_by_id(db, contact_id) }
      if contact
        match = { score: 100, reason: 'ручная связь с контактом', contact: contact }
      end
    end
    match ||= best_contact_match(attrs)
    return clear_uute_link_fields unless match && match[:score] >= 55

    links = UuteDB.with_db { |db| UuteDB.links_for_contact(db, match[:contact]['id']) }
    linked = links.filter_map do |link|
      uute = UuteDB.with_db { |db| UuteDB.find(db, link['uute_id']) }
      next unless uute

      { link: link, uute: uute }
    end
    selected = linked.find { |item| !item[:uute]['nearest_verification_date'].to_s.strip.empty? } || linked.first
    return clear_uute_link_fields.merge('contact_id' => match[:contact]['id'], 'uute_match_note' => match[:reason]) unless selected

    {
      'contact_id' => match[:contact]['id'],
      'uute_id' => selected[:uute]['id'],
      'uute_verification_until' => selected[:uute]['nearest_verification_date'].to_s,
      'uute_match_note' => [match[:reason], selected[:link]['match_reason']].compact.reject(&:empty?).join('; ')
    }
  end
  private_class_method :uute_link_fields

  def clear_uute_link_fields
    {
      'contact_id' => nil,
      'uute_id' => nil,
      'uute_verification_until' => '',
      'uute_match_note' => ''
    }
  end
  private_class_method :clear_uute_link_fields

  def best_contact_match(attrs)
    identifier = attrs['identifier'].to_s.strip.downcase
    unless identifier.empty?
      contact = ContactsDB.with_db do |db|
        db.get_first_row(
          "SELECT * FROM contacts WHERE category = 'gspo' AND lower_ru(COALESCE(identifier, '')) = ?",
          [identifier]
        )
      end
      return { score: 100, reason: 'identifier', contact: contact } if contact
    end

    contacts = ContactsDB.with_db do |db|
      db.execute("SELECT * FROM contacts WHERE category = 'gspo'")
    end
    contacts
      .map { |contact| contact_match(attrs, contact).merge(contact: contact) }
      .max_by { |item| item[:score] }
  end
  private_class_method :best_contact_match

  def preserve_manual_links!(db, attrs)
    existing = db.get_first_row('SELECT contact_id, uute_id, uute_verification_until, uute_match_note FROM water_registry_rows WHERE source_key = ?', [attrs['source_key']])
    return attrs unless existing

    if attrs['contact_id'].to_i <= 0 && existing['contact_id'].to_i.positive?
      attrs['contact_id'] = existing['contact_id'].to_i
      attrs['uute_match_note'] = existing['uute_match_note'].to_s unless existing['uute_match_note'].to_s.empty?
    end
    if attrs['uute_id'].to_i <= 0 && existing['uute_id'].to_i.positive?
      attrs['uute_id'] = existing['uute_id'].to_i
      attrs['uute_verification_until'] = existing['uute_verification_until'].to_s
    end
    attrs
  end
  private_class_method :preserve_manual_links!

  def contact_match(attrs, contact)
    row_name = normalize_name(attrs['gspo_name'])
    contact_name = normalize_name(contact['name'])
    row_address = normalize_address(attrs['standalone_address'])
    contact_address = normalize_address(contact['address'])
    row_leader = normalize_text(attrs['leader_name'])
    contact_consumer = normalize_text(contact['consumer'])

    score = 0
    reasons = []

    if !row_name.empty? && row_name == contact_name
      score += 55
      reasons << 'название'
    elsif token_overlap(row_name, contact_name) >= 0.7
      score += 35
      reasons << 'похожее название'
    elsif contains_token_name?(row_name, contact_name)
      score += 25
      reasons << 'часть названия'
    end

    if !row_address.empty? && row_address == contact_address
      score += 35
      reasons << 'адрес'
    elsif address_close?(row_address, contact_address)
      score += 20
      reasons << 'похожий адрес'
    end

    if !row_leader.empty? && !contact_consumer.empty? && token_overlap(row_leader, contact_consumer) >= 0.5
      score += 10
      reasons << 'председатель'
    end

    { score: [score, 100].min, reason: reasons.join(', ') }
  end
  private_class_method :contact_match

  def public_row(row, detail: false)
    result = row.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
    result[:raw] = parse_json(row['raw_json']) if detail
    result.delete(:raw_json) unless detail
    result
  end
  private_class_method :public_row

  def source_key(attrs)
    identifier = attrs['identifier'].to_s.strip
    return "identifier:#{identifier.downcase}" unless identifier.empty?

    "fallback:#{attrs['source_row']}:#{attrs['gspo_name'].to_s.downcase}:#{attrs['standalone_address'].to_s.downcase}"
  end
  private_class_method :source_key

  def point_group(value)
    value.to_s.strip.split(/[.,]/, 2).first.to_s.strip
  end
  private_class_method :point_group

  def raw_row(sheet, row_index)
    XLSX_COLUMNS.each_with_object({}) do |(key, column), memo|
      value = cell_value(sheet.cell(row_index, column))
      memo[key] = value unless value.empty?
    end
  end
  private_class_method :raw_row

  def header_columns(sheet, row_index = 1)
    (1..sheet.last_column.to_i).each_with_object({}) do |column, memo|
      header = normalize_header(cell_value(sheet.cell(row_index, column)))
      next if header.empty?

      memo[header] ||= column
    end
  end
  private_class_method :header_columns

  def require_header!(columns, header)
    columns.fetch(normalize_header(header)) do
      raise ArgumentError, "в файле не найден столбец «#{header}»"
    end
  end
  private_class_method :require_header!

  def normalize_header(value)
    normalize_text(value).gsub(/\s+/, ' ').strip
  end
  private_class_method :normalize_header

  def cell_value(value)
    case value
    when Date, DateTime
      value.strftime('%d.%m.%Y')
    when Time
      value.strftime('%d.%m.%Y')
    when Float
      value % 1 == 0 ? value.to_i.to_s : value.to_s
    when Integer
      value.to_s
    else
      value.to_s.strip
    end
  end
  private_class_method :cell_value

  def all_yes?(attrs, keys)
    keys.all? { |key| yes?(attrs[key]) }
  end
  private_class_method :all_yes?

  def yes?(value)
    normalize_text(value) == 'да'
  end
  private_class_method :yes?

  def normalize_name(value)
    normalize_text(value)
      .gsub(/\bгспо\b/, ' ')
      .gsub(/\bигб\b/, ' ')
      .gsub(/\bкооператив\b/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end
  private_class_method :normalize_name

  def normalize_address(value)
    normalize_text(value)
      .gsub(/\bул\b/, ' ')
      .gsub(/\bстр\b/, ' ')
      .gsub(/\bстроение\b/, ' ')
      .gsub(/\bпр\b/, ' ')
      .gsub(/\bпроезд\b/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end
  private_class_method :normalize_address

  def normalize_text(value)
    value.to_s
      .downcase
      .tr('ё', 'е')
      .gsub(/[«»"№.,()\/\\_-]+/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end
  private_class_method :normalize_text

  def token_overlap(left, right)
    a = left.split(/\s+/).reject { |token| token.length < 2 }
    b = right.split(/\s+/).reject { |token| token.length < 2 }
    return 0.0 if a.empty? || b.empty?

    (a & b).size.to_f / [a.size, b.size].max
  end
  private_class_method :token_overlap

  def contains_token_name?(left, right)
    return false if left.empty? || right.empty?

    left.include?(right) || right.include?(left)
  end
  private_class_method :contains_token_name?

  def address_close?(left, right)
    return false if left.empty? || right.empty?

    token_overlap(left, right) >= 0.55 || left.include?(right) || right.include?(left)
  end
  private_class_method :address_close?

  def parse_json(value)
    JSON.parse(value.to_s)
  rescue JSON::ParserError, TypeError
    {}
  end
  private_class_method :parse_json

  def iso_date(value)
    raw = value.to_s.strip
    return nil if raw.empty?

    Date.iso8601(raw).iso8601
  rescue ArgumentError
    nil
  end
  private_class_method :iso_date
end
