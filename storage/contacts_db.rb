# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module ContactsDB
  module_function

  CATEGORIES = %w[uk_tsj gspo phys legal budget iglakovo embedded bu2].freeze

  CATEGORY_LABELS = {
    'uk_tsj'   => 'УК и ТСЖ',
    'gspo'     => 'ГСПО',
    'phys'     => 'Прочие ФЛ',
    'legal'    => 'Прочие ЮЛ',
    'budget'   => 'Бюджет',
    'iglakovo' => 'Иглаково (коттеджи)',
    'embedded' => 'Встроенные помещения',
    'bu2'      => 'БУ-2'
  }.freeze

  DEFAULT_CATEGORY_ORDER = CATEGORIES.each_with_index.to_h.freeze

  @db_mutex = Mutex.new

  def db_path
    raw = ENV['CONTACTS_DB_PATH'].to_s.strip
    raw = './storage/contacts.db' if raw.empty?
    File.expand_path(raw, File.dirname(__dir__))
  end

  def with_db
    @db_mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(db_path))
      db = SQLite3::Database.new(db_path)
      db.busy_timeout = 5_000
      db.execute('PRAGMA foreign_keys = ON')
      db.execute('PRAGMA journal_mode = WAL')
      db.results_as_hash = true
      register_unicode_helpers(db)
      ensure_schema(db)
      begin
        yield db
      ensure
        db.close
      end
    end
  end

  def register_unicode_helpers(db)
    db.create_function('lower_ru', 1) do |func, value|
      s = value.to_s
      s = s.dup.force_encoding('UTF-8') unless s.encoding == Encoding::UTF_8
      func.result = s.downcase
    end
  end

  def ensure_schema(db)
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS contacts (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        category         TEXT NOT NULL,
        name             TEXT,
        connection_point TEXT,
        consumer         TEXT,
        manager          TEXT,
        address          TEXT,
        phone            TEXT,
        phone_alt        TEXT,
        email            TEXT,
        postal_address   TEXT,
        notes            TEXT,
        identifier       TEXT,
        metering_presence TEXT,
        disconnected     TEXT,
        sync_status      TEXT,
        sync_note        TEXT,
        source_row       INTEGER,
        updated_at       INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_contacts_category ON contacts(category);
      CREATE INDEX IF NOT EXISTS idx_contacts_addr     ON contacts(address);
      CREATE INDEX IF NOT EXISTS idx_contacts_name     ON contacts(name);

      CREATE TABLE IF NOT EXISTS contacts_meta (
        key   TEXT PRIMARY KEY,
        value TEXT
      );

      CREATE TABLE IF NOT EXISTS contact_categories (
        key        TEXT PRIMARY KEY,
        label      TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        system     INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    SQL

    columns = db.execute('PRAGMA table_info(contacts)').map { |row| row['name'] }
    db.execute('ALTER TABLE contacts ADD COLUMN email TEXT') unless columns.include?('email')
    db.execute('ALTER TABLE contacts ADD COLUMN postal_address TEXT') unless columns.include?('postal_address')
    db.execute('ALTER TABLE contacts ADD COLUMN identifier TEXT') unless columns.include?('identifier')
    db.execute('ALTER TABLE contacts ADD COLUMN metering_presence TEXT') unless columns.include?('metering_presence')
    db.execute('ALTER TABLE contacts ADD COLUMN disconnected TEXT') unless columns.include?('disconnected')
    db.execute('ALTER TABLE contacts ADD COLUMN sync_status TEXT') unless columns.include?('sync_status')
    db.execute('ALTER TABLE contacts ADD COLUMN sync_note TEXT') unless columns.include?('sync_note')
    db.execute('CREATE INDEX IF NOT EXISTS idx_contacts_identifier ON contacts(identifier)')
    seed_contact_categories(db)
  end

  def seed_contact_categories(db)
    now = Time.now.to_i
    CATEGORIES.each_with_index do |key, index|
      label = CATEGORY_LABELS[key] || key
      row = db.get_first_row('SELECT key FROM contact_categories WHERE key = ?', [key])
      if row
        db.execute(
          'UPDATE contact_categories SET label = ?, sort_order = ?, system = 1, updated_at = ? WHERE key = ?',
          [label, index, now, key]
        )
      else
        db.execute(
          'INSERT INTO contact_categories(key, label, sort_order, system, created_at, updated_at) VALUES(?, ?, ?, 1, ?, ?)',
          [key, label, index, now, now]
        )
      end
    end
  end
  private_class_method :seed_contact_categories

  def categories(db)
    db.execute('SELECT key, label, sort_order, system, created_at, updated_at FROM contact_categories ORDER BY sort_order, label, key')
  end

  def category_keys(db)
    categories(db).map { |row| row['key'].to_s }
  end

  def category_exists?(db, key)
    !!db.get_first_row('SELECT 1 FROM contact_categories WHERE key = ?', [key.to_s])
  end

  def category_by_key(db, key)
    db.get_first_row('SELECT key, label, sort_order, system, created_at, updated_at FROM contact_categories WHERE key = ?', [key.to_s])
  end

  def create_category(db, key:, label:, sort_order: nil)
    k = key.to_s.strip
    l = label.to_s.strip
    raise ArgumentError, 'Ключ категории обязателен' if k.empty?
    raise ArgumentError, 'Название категории обязательно' if l.empty?
    raise ArgumentError, 'Категория с таким ключом уже есть' if category_exists?(db, k)

    order = sort_order.nil? ? next_category_order(db) : sort_order.to_i
    now = Time.now.to_i
    db.execute(
      'INSERT INTO contact_categories(key, label, sort_order, system, created_at, updated_at) VALUES(?, ?, ?, 0, ?, ?)',
      [k, l, order, now, now]
    )
    category_by_key(db, k)
  end

  def update_category(db, key, attrs)
    row = category_by_key(db, key)
    return nil unless row

    label = attrs.key?('label') ? attrs['label'].to_s.strip : row['label'].to_s
    raise ArgumentError, 'Название категории обязательно' if label.empty?

    sort_order = attrs.key?('sort_order') ? attrs['sort_order'].to_i : row['sort_order'].to_i
    db.execute(
      'UPDATE contact_categories SET label = ?, sort_order = ?, updated_at = ? WHERE key = ?',
      [label, sort_order, Time.now.to_i, key.to_s]
    )
    category_by_key(db, key)
  end

  def delete_category(db, key)
    row = category_by_key(db, key)
    return nil unless row
    raise ArgumentError, 'Системную категорию удалить нельзя' if row['system'].to_i == 1
    raise ArgumentError, 'В категории есть контакты' if count_in_category(db, key).positive?

    db.execute('DELETE FROM contact_categories WHERE key = ?', [key.to_s])
    row
  end

  def next_category_order(db)
    max = db.get_first_value('SELECT MAX(sort_order) FROM contact_categories').to_i
    max + 10
  end
  private_class_method :next_category_order

  def replace_category(db, category, rows)
    db.execute('BEGIN')
    existing_rows = db.execute('SELECT * FROM contacts WHERE category = ?', [category])
    existing_by_source_row = {}
    existing_by_fingerprint = {}
    existing_by_identifier = {}
    existing_rows.each do |row|
      sr = row['source_row']
      existing_by_source_row[sr.to_i] = row if sr
      idf = row['identifier'].to_s.strip.downcase
      existing_by_identifier[idf] = row unless idf.empty?
      fp = contact_fingerprint(
        category: category,
        name: row['name'],
        connection_point: row['connection_point'],
        consumer: row['consumer'],
        manager: row['manager'],
        address: row['address']
      )
      existing_by_fingerprint[fp] = row unless fp.empty?
    end

    update_stmt = db.prepare(<<~SQL)
      UPDATE contacts SET
        name = ?, connection_point = ?, consumer = ?, manager = ?, address = ?,
        phone = ?, phone_alt = ?, email = ?, postal_address = ?, notes = ?, identifier = ?,
        metering_presence = ?, disconnected = ?, sync_status = ?, sync_note = ?, source_row = ?, updated_at = ?
      WHERE id = ?
    SQL
    insert_stmt = db.prepare(<<~SQL)
      INSERT INTO contacts
        (category, name, connection_point, consumer, manager, address,
         phone, phone_alt, email, postal_address, notes, identifier, metering_presence, disconnected, sync_status, sync_note, source_row, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    now = Time.now.to_i
    matched_ids = {}
    rows.each do |r|
      source_row = r[:source_row]
      fp = contact_fingerprint(
        category: category,
        name: r[:name],
        connection_point: r[:connection_point],
        consumer: r[:consumer],
        manager: r[:manager],
        address: r[:address]
      )
      incoming_identifier = r[:identifier].to_s.strip.downcase
      previous = existing_by_identifier[incoming_identifier] ||
                 existing_by_source_row[source_row.to_i] ||
                 existing_by_fingerprint[fp]

      # UID из карточки не перезаписываем: для существующей записи всегда сохраняем текущий identifier.
      identifier = if previous
                     previous['identifier']
                   else
                     preferred_value(r[:identifier], nil)
                   end
      metering_presence = preferred_value(r[:metering_presence], previous && previous['metering_presence'])
      disconnected = preferred_value(r[:disconnected], previous && previous['disconnected'])
      values = [
        r[:name], r[:connection_point], r[:consumer], r[:manager], r[:address],
        clean_phone_text(r[:phone]), clean_phone_text(r[:phone_alt]), r[:email], r[:postal_address], r[:notes], identifier, metering_presence, disconnected, 'ok', nil, source_row, now
      ]

      if previous
        update_stmt.execute(*(values + [previous['id']]))
        matched_ids[previous['id'].to_i] = true
      else
        insert_stmt.execute(category, *values)
        matched_ids[db.last_insert_row_id.to_i] = true
      end
    end

    stale_ids = existing_rows.map { |row| row['id'].to_i }.reject { |id| matched_ids[id] }
    unless stale_ids.empty?
      placeholders = (['?'] * stale_ids.size).join(', ')
      db.execute(
        "UPDATE contacts SET sync_status = 'not_matched', sync_note = ?, updated_at = ? WHERE id IN (#{placeholders})",
        ["Синхронизация не прошла: запись не сопоставлена с текущим Excel", now] + stale_ids
      )
    end

    update_stmt.close
    insert_stmt.close
    db.execute('COMMIT')
  rescue StandardError => e
    db.execute('ROLLBACK') rescue nil
    raise e
  end

  def set_meta(db, key, value)
    db.execute(
      'INSERT INTO contacts_meta(key, value) VALUES(?, ?) ' \
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key.to_s, value.to_s]
    )
  end

  def get_meta(db, key)
    row = db.get_first_row('SELECT value FROM contacts_meta WHERE key = ?', [key.to_s])
    row && row['value']
  end

  def count_by_category(db)
    rows = db.execute('SELECT category, COUNT(*) AS c FROM contacts GROUP BY category')
    rows.each_with_object({}) { |r, h| h[r['category']] = r['c'].to_i }
  end

  def list_by_category(db, category, limit:, offset:)
    sort_expr = category_sort_expr(category)

    db.execute(
      "SELECT * FROM contacts WHERE category = ? " \
      "ORDER BY #{sort_expr}, id " \
      "LIMIT ? OFFSET ?",
      [category, limit, offset]
    )
  end

  def all_by_category(db, category)
    sort_expr = category_sort_expr(category)

    db.execute(
      "SELECT * FROM contacts WHERE category = ? " \
      "ORDER BY #{sort_expr}, id",
      [category]
    )
  end

  def count_in_category(db, category)
    row = db.get_first_row('SELECT COUNT(*) AS c FROM contacts WHERE category = ?', [category])
    row ? row['c'].to_i : 0
  end

  def search_by_category(db, category, query, limit:, offset:)
    q = "%#{query.to_s.downcase}%"
    sort_expr = category_sort_expr(category)
    db.execute(
      "SELECT * FROM contacts WHERE category = ? AND #{search_where} " \
      "ORDER BY #{sort_expr}, id " \
      "LIMIT ? OFFSET ?",
      [category, q, q, q, q, q, q, q, q, q, q, q, limit, offset]
    )
  end

  def count_search_in_category(db, category, query)
    q = "%#{query.to_s.downcase}%"
    row = db.get_first_row(
      "SELECT COUNT(*) AS c FROM contacts WHERE category = ? AND #{search_where}",
      [category, q, q, q, q, q, q, q, q, q, q, q]
    )
    row ? row['c'].to_i : 0
  end

  def find_by_id(db, id)
    db.get_first_row('SELECT * FROM contacts WHERE id = ?', [id.to_i])
  end

  def update_by_id(db, id, attrs)
    allowed = %w[name connection_point consumer manager address phone phone_alt email postal_address notes identifier metering_presence disconnected]
    values = attrs.each_with_object({}) do |(key, value), memo|
      k = key.to_s
      next unless allowed.include?(k)

      v = clean_contact_value(k, value)
      memo[k] = v.empty? ? nil : v
    end
    return find_by_id(db, id) if values.empty?

    values['updated_at'] = Time.now.to_i
    assignments = values.keys.map { |k| "#{k} = ?" }.join(', ')
    db.execute(
      "UPDATE contacts SET #{assignments} WHERE id = ?",
      values.values + [id.to_i]
    )
    find_by_id(db, id)
  end

  def create(db, category, attrs)
    allowed = %w[name connection_point consumer manager address phone phone_alt email postal_address notes identifier metering_presence disconnected]
    values = allowed.each_with_object({}) do |key, memo|
      v = clean_contact_value(key, attrs[key])
      memo[key] = v.empty? ? nil : v
    end
    now = Time.now.to_i

    db.execute(
      'INSERT INTO contacts ' \
      '(category, name, connection_point, consumer, manager, address, phone, phone_alt, email, postal_address, notes, identifier, metering_presence, disconnected, source_row, updated_at) ' \
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)',
      [
        category,
        values['name'],
        values['connection_point'],
        values['consumer'],
        values['manager'],
        values['address'],
        values['phone'],
        values['phone_alt'],
        values['email'],
        values['postal_address'],
        values['notes'],
        values['identifier'],
        values['metering_presence'],
        values['disconnected'],
        now
      ]
    )
    find_by_id(db, db.last_insert_row_id)
  end

  def delete_by_id(db, id)
    record = find_by_id(db, id)
    return nil unless record

    db.execute('DELETE FROM contacts WHERE id = ?', [id.to_i])
    record
  end

  def update_identifier(db, id, identifier)
    db.execute(
      'UPDATE contacts SET identifier = ?, updated_at = ? WHERE id = ?',
      [identifier.to_s.strip.empty? ? nil : identifier.to_s.strip, Time.now.to_i, id.to_i]
    )
    find_by_id(db, id)
  end

  def update_metering_presence(db, id, metering_presence)
    db.execute(
      'UPDATE contacts SET metering_presence = ?, updated_at = ? WHERE id = ?',
      [metering_presence.to_s.strip.empty? ? nil : metering_presence.to_s.strip, Time.now.to_i, id.to_i]
    )
    find_by_id(db, id)
  end

  def search(db, query, limit:)
    q = "%#{query.to_s.downcase}%"
    db.execute(
      "SELECT * FROM contacts WHERE #{search_where} " \
      'ORDER BY category, COALESCE(NULLIF(TRIM(address), \'\'), \'\') ' \
      'LIMIT ?',
      [q, q, q, q, q, q, q, q, q, q, q, limit]
    )
  end

  def category_sort_expr(category)
    case category
    when 'gspo'     then "COALESCE(NULLIF(TRIM(address), ''), name, '')"
    when 'phys'     then "COALESCE(NULLIF(TRIM(consumer), ''), address, '')"
    when 'iglakovo' then "COALESCE(NULLIF(TRIM(name), ''), address, '')"
    else                 "COALESCE(NULLIF(TRIM(name), ''), address, '')"
    end
  end
  private_class_method :category_sort_expr

  def search_where
    '(' \
      'lower_ru(COALESCE(name, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(address, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(consumer, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(manager, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(connection_point, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(phone, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(phone_alt, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(email, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(postal_address, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(identifier, \'\')) LIKE ? OR ' \
      'lower_ru(COALESCE(metering_presence, \'\')) LIKE ?' \
    ')'
  end
  private_class_method :search_where

  def clean_contact_value(key, value)
    return clean_phone_text(value) if %w[phone phone_alt].include?(key.to_s)

    value.to_s.strip
  end
  private_class_method :clean_contact_value

  def preferred_value(primary, fallback)
    p = primary.to_s.strip
    return p unless p.empty?

    f = fallback.to_s.strip
    return nil if f.empty?

    f
  end
  private_class_method :preferred_value

  def contact_fingerprint(category:, name:, connection_point:, consumer:, manager:, address:)
    fields =
      if category.to_s == 'gspo'
        [name, address]
      else
        [name, consumer, manager, address, connection_point]
      end
    normalized = fields.map { |value| normalize_identity_text(value) }.reject(&:empty?)
    normalized.join('|')
  end
  private_class_method :contact_fingerprint

  def normalize_identity_text(value)
    value.to_s.downcase.tr('ё', 'е').gsub(/[^[:alnum:]а-я]+/, ' ').gsub(/\s+/, ' ').strip
  end
  private_class_method :normalize_identity_text

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
  private_class_method :clean_phone_text
end
