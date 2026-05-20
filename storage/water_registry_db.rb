# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module WaterRegistryDB
  module_function

  @db_mutex = Mutex.new

  def db_path
    raw = ENV['WATER_REGISTRY_DB_PATH'].to_s.strip
    raw = './storage/water_registry.db' if raw.empty?
    File.expand_path(raw, File.dirname(__dir__))
  end

  def with_db
    @db_mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(db_path))
      db = SQLite3::Database.new(db_path)
      db.busy_timeout = 5_000
      db.execute('PRAGMA journal_mode = WAL')
      db.results_as_hash = true
      register_unicode_helpers(db)
      register_numeric_point(db)
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
      CREATE TABLE IF NOT EXISTS water_registry_rows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_key TEXT NOT NULL UNIQUE,
        source_row INTEGER,
        point_number TEXT,
        identifier TEXT,
        object_id INTEGER,
        actual_connection_point TEXT,
        connected TEXT,
        point_filter TEXT,
        gspo_count_in_point TEXT,
        gspo_name TEXT,
        standalone_address TEXT,
        leader_name TEXT,
        phone TEXT,
        metering_presence TEXT,
        application TEXT,
        application_date TEXT,
        no_debt TEXT,
        power_of_attorney TEXT,
        contract TEXT,
        uute TEXT,
        uute_verified TEXT,
        third_party_disconnection TEXT,
        third_party_disconnection_note TEXT,
        payment TEXT,
        payment_date TEXT,
        water_supplied TEXT,
        verdict TEXT,
        note TEXT,
        all_except_payment TEXT,
        tf_in_ts TEXT,
        tf_in_ts_date TEXT,
        connection_act TEXT,
        illegal_connection_2025 TEXT,
        illegal_connection_2026 TEXT,
        contact_id INTEGER,
        uute_id INTEGER,
        uute_verification_until TEXT,
        uute_match_note TEXT,
        raw_json TEXT,
        imported_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_water_registry_point ON water_registry_rows(point_number);
      CREATE INDEX IF NOT EXISTS idx_water_registry_name ON water_registry_rows(gspo_name);
      CREATE INDEX IF NOT EXISTS idx_water_registry_identifier ON water_registry_rows(identifier);

      CREATE TABLE IF NOT EXISTS water_registry_imports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT,
        imported_at INTEGER NOT NULL,
        added_count INTEGER NOT NULL,
        updated_count INTEGER NOT NULL,
        skipped_count INTEGER NOT NULL,
        total_rows INTEGER NOT NULL
      );
    SQL

    columns = db.execute('PRAGMA table_info(water_registry_rows)').map { |row| row['name'] }
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN third_party_disconnection_note TEXT') unless columns.include?('third_party_disconnection_note')
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN application_date TEXT') unless columns.include?('application_date')
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN water_supplied TEXT') unless columns.include?('water_supplied')
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN tf_in_ts_date TEXT') unless columns.include?('tf_in_ts_date')
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN payment_date TEXT') unless columns.include?('payment_date')
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN uute_verified TEXT') unless columns.include?('uute_verified')
    db.execute('ALTER TABLE water_registry_rows ADD COLUMN object_id INTEGER') unless columns.include?('object_id')
    db.execute('CREATE INDEX IF NOT EXISTS idx_water_registry_object_id ON water_registry_rows(object_id)')
  end

  def upsert_row(db, attrs)
    now = Time.now.to_i
    existing = db.get_first_row('SELECT id FROM water_registry_rows WHERE source_key = ?', [attrs['source_key']])
    attrs = attrs.merge('updated_at' => now)

    if existing
      assignments = attrs.keys.reject { |key| key == 'source_key' }.map { |key| "#{key} = ?" }.join(', ')
      values = attrs.reject { |key, _| key == 'source_key' }.values + [attrs['source_key']]
      db.execute("UPDATE water_registry_rows SET #{assignments} WHERE source_key = ?", values)
      :updated
    else
      attrs = attrs.merge('imported_at' => now)
      keys = attrs.keys
      placeholders = (['?'] * keys.size).join(', ')
      db.execute(
        "INSERT INTO water_registry_rows (#{keys.join(', ')}) VALUES (#{placeholders})",
        attrs.values
      )
      :added
    end
  end

  def create(db, attrs)
    now = Time.now.to_i
    attrs = attrs.merge('imported_at' => now, 'updated_at' => now)
    keys = attrs.keys
    placeholders = (['?'] * keys.size).join(', ')
    db.execute(
      "INSERT INTO water_registry_rows (#{keys.join(', ')}) VALUES (#{placeholders})",
      attrs.values
    )
    find(db, db.last_insert_row_id)
  end

  def record_import(db, filename:, added:, updated:, skipped:, total:)
    db.execute(
      'INSERT INTO water_registry_imports(filename, imported_at, added_count, updated_count, skipped_count, total_rows) VALUES (?, ?, ?, ?, ?, ?)',
      [filename.to_s, Time.now.to_i, added.to_i, updated.to_i, skipped.to_i, total.to_i]
    )
  end

  def last_import(db)
    db.get_first_row('SELECT * FROM water_registry_imports ORDER BY imported_at DESC LIMIT 1')
  end

  def count(db, query: nil, point: nil, payment_from: nil, payment_to: nil, application_from: nil, application_to: nil)
    where, values = filters(
      query: query, point: point,
      payment_from: payment_from, payment_to: payment_to,
      application_from: application_from, application_to: application_to
    )
    db.get_first_value("SELECT COUNT(*) FROM water_registry_rows #{where}", values).to_i
  end

  def list(db, limit:, offset:, query: nil, point: nil, sort: nil, dir: nil, payment_from: nil, payment_to: nil, application_from: nil, application_to: nil)
    where, values = filters(
      query: query, point: point,
      payment_from: payment_from, payment_to: payment_to,
      application_from: application_from, application_to: application_to
    )
    db.execute(
      "SELECT * FROM water_registry_rows #{where} ORDER BY #{order_clause(sort: sort, dir: dir)} LIMIT ? OFFSET ?",
      values + [limit, offset]
    )
  end

  def paid_between(db, payment_from:, payment_to:)
    where, values = filters(query: nil, point: nil, payment_from: payment_from, payment_to: payment_to)
    payment_clause = where.empty? ? 'WHERE' : "#{where} AND"
    db.execute(
      "SELECT * FROM water_registry_rows #{payment_clause} COALESCE(payment_date, '') <> '' ORDER BY numeric_point(actual_connection_point), numeric_point(point_number), gspo_name, id",
      values
    )
  end

  def find(db, id)
    db.get_first_row('SELECT * FROM water_registry_rows WHERE id = ?', [id.to_i])
  end

  def rows_for_contact(db, contact_id)
    db.execute(
      'SELECT * FROM water_registry_rows WHERE contact_id = ? ORDER BY numeric_point(point_number), gspo_name, id',
      [contact_id.to_i]
    )
  end

  def update(db, id, attrs)
    allowed = editable_fields
    values = attrs.each_with_object({}) do |(key, value), memo|
      k = key.to_s
      next unless allowed.include?(k)

      memo[k] = if %w[contact_id uute_id].include?(k)
                  value.to_s.strip.empty? ? nil : value.to_i
                else
                  value.to_s.strip
                end
    end
    return find(db, id) if values.empty?

    values['updated_at'] = Time.now.to_i
    assignments = values.keys.map { |key| "#{key} = ?" }.join(', ')
    db.execute("UPDATE water_registry_rows SET #{assignments} WHERE id = ?", values.values + [id.to_i])
    find(db, id)
  end

  def normalize_metering_flags(db)
    now = Time.now.to_i
    db.execute(
      "UPDATE water_registry_rows SET uute = 'нет', uute_id = NULL, uute_verification_until = '', uute_match_note = '', updated_at = ? WHERE lower_ru(COALESCE(metering_presence, '')) = 'нет'",
      [now]
    )
    db.execute(
      "UPDATE water_registry_rows SET uute = 'да', updated_at = ? WHERE lower_ru(COALESCE(metering_presence, '')) <> 'нет'",
      [now]
    )
  end

  def editable_fields
    %w[
      point_number actual_connection_point connected point_filter gspo_count_in_point
      leader_name phone metering_presence application application_date no_debt power_of_attorney contract uute
      uute_verified
      third_party_disconnection third_party_disconnection_note payment payment_date water_supplied verdict note all_except_payment tf_in_ts tf_in_ts_date connection_act
      illegal_connection_2025 illegal_connection_2026 contact_id uute_id uute_verification_until uute_match_note
    ]
  end

  def filters(query:, point:, payment_from:, payment_to:, application_from: nil, application_to: nil)
    clauses = []
    values = []

    unless query.to_s.strip.empty?
      q = "%#{query.to_s.downcase.strip}%"
      clauses << '(' \
        "lower_ru(COALESCE(gspo_name, '')) LIKE ? OR " \
        "lower_ru(COALESCE(standalone_address, '')) LIKE ? OR " \
        "lower_ru(COALESCE(leader_name, '')) LIKE ? OR " \
        "lower_ru(COALESCE(phone, '')) LIKE ?" \
      ')'
      values.concat([q, q, q, q])
    end

    unless point.to_s.strip.empty?
      p = point.to_s.strip
      clauses << '(point_number = ? OR actual_connection_point = ? OR actual_connection_point LIKE ? OR point_filter = ?)'
      values.concat([p, p, "#{p}.%", p])
    end

    unless payment_from.to_s.strip.empty?
      clauses << "payment_date >= ?"
      values << payment_from.to_s.strip
    end

    unless payment_to.to_s.strip.empty?
      clauses << "payment_date <= ?"
      values << payment_to.to_s.strip
    end

    unless application_from.to_s.strip.empty?
      clauses << "application_date >= ?"
      values << application_from.to_s.strip
    end

    unless application_to.to_s.strip.empty?
      clauses << "application_date <= ?"
      values << application_to.to_s.strip
    end

    [clauses.empty? ? '' : "WHERE #{clauses.join(' AND ')}", values]
  end
  private_class_method :filters

  def order_clause(sort:, dir:)
    direction = dir.to_s.downcase == 'desc' ? 'DESC' : 'ASC'
    return "lower_ru(COALESCE(metering_presence, '')) #{direction}, numeric_point(point_number), COALESCE(NULLIF(TRIM(gspo_name), ''), standalone_address, '')" if sort.to_s == 'metering_presence'

    "numeric_point(point_number), COALESCE(NULLIF(TRIM(gspo_name), ''), standalone_address, '')"
  end
  private_class_method :order_clause

  def disconnected_points(db)
    db.execute(<<~SQL).map { |row| row['point'].to_s.strip }.reject(&:empty?)
      SELECT DISTINCT TRIM(actual_connection_point) AS point
      FROM water_registry_rows
      WHERE lower_ru(COALESCE(water_supplied, '')) != 'да'
        AND COALESCE(TRIM(actual_connection_point), '') != ''
      ORDER BY numeric_point(point)
    SQL
  end

  def cascade_water_supplied(db, point, value)
    now = Time.now.to_i
    db.execute(
      "UPDATE water_registry_rows SET water_supplied = ?, updated_at = ? WHERE TRIM(actual_connection_point) = ?",
      [value, now, point]
    )
  end

  def normalize_water_supplied_flags(db)
    now = Time.now.to_i
    db.execute(
      "UPDATE water_registry_rows SET water_supplied = 'нет', updated_at = ? WHERE COALESCE(water_supplied, '') = ''",
      [now]
    )
  end

  def register_numeric_point(db)
    db.create_function('numeric_point', 1) do |func, value|
      func.result = value.to_s.gsub(',', '.').to_f
    end
  end
end
