# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module UuteDB
  module_function

  @db_mutex = Mutex.new

  def db_path
    raw = ENV['UUTE_DB_PATH'].to_s.strip
    raw = './storage/uute.db' if raw.empty?
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
      CREATE TABLE IF NOT EXISTS uute_objects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL DEFAULT 'gspo',
        source_key TEXT NOT NULL UNIQUE,
        source_row INTEGER,
        list_number TEXT,
        contract_number TEXT,
        name TEXT,
        address TEXT,
        identifier TEXT,
        object_id INTEGER,
        input_kind TEXT,
        merge_note TEXT,
        note TEXT,
        not_allowed TEXT,
        not_allowed_reason TEXT,
        periods_json TEXT,
        date_input_uute TEXT,
        admit_until TEXT,
        date_output_uute TEXT,
        output_reason TEXT,
        act_primary_number TEXT,
        act_periodic_number TEXT,
        act_output_number TEXT,
        registration_date TEXT,
        dm_installation TEXT,
        violations TEXT,
        violation_fixed_date TEXT,
        verifier TEXT,
        documents TEXT,
        operating_time TEXT,
        project TEXT,
        project_approval TEXT,
        act_date TEXT,
        input_date TEXT,
        previous_act_date TEXT,
        inspection_date TEXT,
        heat_load TEXT,
        hot_water_load TEXT,
        ventilation_load TEXT,
        contract_flow TEXT,
        distance TEXT,
        diameter TEXT,
        connection_point_number TEXT,
        installation_point TEXT,
        losses_before_uute TEXT,
        losses_after_uute TEXT,
        calculator_type TEXT,
        flowmeter_1 TEXT,
        flowmeter_2 TEXT,
        temp_sensor_1 TEXT,
        temp_sensor_2 TEXT,
        pressure_sensor_1 TEXT,
        pressure_sensor_2 TEXT,
        calculator_serial TEXT,
        flowmeter_serial_1 TEXT,
        flowmeter_serial_2 TEXT,
        temp_sensor_serial_1 TEXT,
        temp_sensor_serial_2 TEXT,
        pressure_sensor_serial_1 TEXT,
        pressure_sensor_serial_2 TEXT,
        calculator_verification_date TEXT,
        flowmeter_verification_date_1 TEXT,
        flowmeter_verification_date_2 TEXT,
        temp_sensor_verification_date_1 TEXT,
        temp_sensor_verification_date_2 TEXT,
        pressure_sensor_verification_date_1 TEXT,
        pressure_sensor_verification_date_2 TEXT,
        nearest_verification_date TEXT,
        seal_calculator TEXT,
        seal_flowmeter_1 TEXT,
        seal_flowmeter_2 TEXT,
        seal_temp_sensor_1 TEXT,
        seal_temp_sensor_2 TEXT,
        seal_cut_1 TEXT,
        seal_cut_2 TEXT,
        seal_cut_3 TEXT,
        seal_cut_4 TEXT,
        seals_checked TEXT,
        system_type TEXT,
        service_org TEXT,
        readings_date TEXT,
        reading_q TEXT,
        reading_m1 TEXT,
        reading_v1 TEXT,
        reading_m2 TEXT,
        reading_v2 TEXT,
        reading_t1 TEXT,
        reading_t2 TEXT,
        reading_p1 TEXT,
        reading_p2 TEXT,
        accepted_position TEXT,
        accepted_by TEXT,
        check_date TEXT,
        check_violations TEXT,
        check_violation_fixed_date TEXT,
        check_note TEXT,
        raw_json TEXT,
        imported_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_uute_category ON uute_objects(category);
      CREATE INDEX IF NOT EXISTS idx_uute_identifier ON uute_objects(identifier);
      CREATE INDEX IF NOT EXISTS idx_uute_contract ON uute_objects(contract_number);
      CREATE INDEX IF NOT EXISTS idx_uute_address ON uute_objects(address);

      CREATE TABLE IF NOT EXISTS uute_imports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT,
        imported_at INTEGER NOT NULL,
        added_count INTEGER NOT NULL,
        updated_count INTEGER NOT NULL,
        skipped_count INTEGER NOT NULL,
        total_rows INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS uute_contact_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uute_id INTEGER NOT NULL,
        contact_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'manual',
        match_score INTEGER,
        match_reason TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(uute_id, contact_id)
      );
      CREATE INDEX IF NOT EXISTS idx_uute_contact_links_uute ON uute_contact_links(uute_id);
      CREATE INDEX IF NOT EXISTS idx_uute_contact_links_contact ON uute_contact_links(contact_id);

      CREATE TABLE IF NOT EXISTS uute_act_counters (
        category TEXT NOT NULL,
        kind TEXT NOT NULL,
        year INTEGER NOT NULL,
        next_number INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (category, kind, year)
      );
    SQL

    columns = db.execute('PRAGMA table_info(uute_objects)').map { |row| row['name'] }
    db.execute('ALTER TABLE uute_objects ADD COLUMN object_id INTEGER') unless columns.include?('object_id')
    db.execute('CREATE INDEX IF NOT EXISTS idx_uute_object_id ON uute_objects(object_id)')
    {
      'flowmeter_3' => 'TEXT',
      'flowmeter_4' => 'TEXT',
      'flowmeter_serial_3' => 'TEXT',
      'flowmeter_serial_4' => 'TEXT',
      'flowmeter_verification_date_3' => 'TEXT',
      'flowmeter_verification_date_4' => 'TEXT',
      'temp_sensor_3' => 'TEXT',
      'temp_sensor_4' => 'TEXT',
      'temp_sensor_serial_3' => 'TEXT',
      'temp_sensor_serial_4' => 'TEXT',
      'temp_sensor_verification_date_3' => 'TEXT',
      'temp_sensor_verification_date_4' => 'TEXT',
      'pressure_sensor_3' => 'TEXT',
      'pressure_sensor_4' => 'TEXT',
      'pressure_sensor_serial_3' => 'TEXT',
      'pressure_sensor_serial_4' => 'TEXT',
      'pressure_sensor_verification_date_3' => 'TEXT',
      'pressure_sensor_verification_date_4' => 'TEXT',
      'seal_cut_5' => 'TEXT',
      'seal_cut_6' => 'TEXT',
      'seal_calculator' => 'TEXT',
      'seal_flowmeter_1' => 'TEXT',
      'seal_flowmeter_2' => 'TEXT',
      'seal_temp_sensor_1' => 'TEXT',
      'seal_temp_sensor_2' => 'TEXT',
      'seal_cut_1' => 'TEXT',
      'seal_cut_2' => 'TEXT',
      'seal_cut_3' => 'TEXT',
      'seal_cut_4' => 'TEXT',
      'act_number' => 'TEXT',
      'calculator_verification_date' => 'TEXT',
      'flowmeter_verification_date_1' => 'TEXT',
      'flowmeter_verification_date_2' => 'TEXT',
      'temp_sensor_verification_date_1' => 'TEXT',
      'temp_sensor_verification_date_2' => 'TEXT',
      'pressure_sensor_verification_date_1' => 'TEXT',
      'pressure_sensor_verification_date_2' => 'TEXT',
      'list_number' => 'TEXT',
      'arshin_checks_json' => 'TEXT',
      'commercial_accounting' => 'TEXT',
      'extra_seals_json' => 'TEXT',
      'seal_flowmeter_3' => 'TEXT',
      'seal_flowmeter_4' => 'TEXT',
      'seal_temp_sensor_3' => 'TEXT',
      'seal_temp_sensor_4' => 'TEXT'
    }.each do |name, type|
      db.execute("ALTER TABLE uute_objects ADD COLUMN #{name} #{type}") unless columns.include?(name)
    end
  end

  def find_by_identifier(db, identifier, category: 'gspo')
    id_norm = identifier.to_s.strip.downcase
    return nil if id_norm.empty?

    db.get_first_row(
      "SELECT * FROM uute_objects WHERE category = ? AND lower_ru(COALESCE(identifier, '')) = ?",
      [category.to_s, id_norm]
    )
  end

  def patch_object(db, id, patch)
    existing = find(db, id.to_i)
    return { status: :not_found, changed_fields: [], changes: {} } unless existing

    patch = patch.transform_keys(&:to_s)
    changes = changes_for(existing, patch)
    return { status: :unchanged, changed_fields: [], changes: {}, id: existing['id'] } if changes.empty?

    now = Time.now.to_i
    keys = patch.keys
    assignments = keys.map { |k| "#{k} = ?" }.join(', ')
    values = patch.values + [now, id.to_i]
    db.execute("UPDATE uute_objects SET #{assignments}, updated_at = ? WHERE id = ?", values)
    { status: :updated, changed_fields: changes.keys, changes: changes, id: existing['id'] }
  end

  def upsert_object(db, attrs)
    now = Time.now.to_i
    existing = db.get_first_row('SELECT * FROM uute_objects WHERE source_key = ?', [attrs['source_key']])

    if existing
      changes = changes_for(existing, attrs)
      return { status: :unchanged, changed_fields: [], changes: {} } if changes.empty?
      changed_fields = changes.keys

      values_to_update = attrs.merge('updated_at' => now)
      assignments = values_to_update.keys.reject { |k| k == 'source_key' }.map { |k| "#{k} = ?" }.join(', ')
      values = values_to_update.reject { |k, _| k == 'source_key' }.values + [attrs['source_key']]
      db.execute("UPDATE uute_objects SET #{assignments} WHERE source_key = ?", values)
      { status: :updated, changed_fields: changed_fields, changes: changes, id: existing['id'] }
    else
      values_to_insert = attrs.merge('imported_at' => now, 'updated_at' => now)
      keys = values_to_insert.keys
      placeholders = (['?'] * keys.size).join(', ')
      db.execute(
        "INSERT INTO uute_objects (#{keys.join(', ')}) VALUES (#{placeholders})",
        values_to_insert.values
      )
      { status: :added, changed_fields: [], changes: {}, id: db.last_insert_row_id }
    end
  end

  def changes_for(existing, attrs)
    ignored = %w[source_key source_row raw_json imported_at updated_at]
    attrs.each_with_object({}) do |(key, value), acc|
      next if ignored.include?(key.to_s)

      existing_value = existing[key].nil? ? '' : existing[key].to_s.strip
      incoming_value = value.nil? ? '' : value.to_s.strip
      if existing_value != incoming_value
        acc[key.to_s] = { before: existing_value, after: incoming_value }
      end
    end
  end
  private_class_method :changes_for

  def object_changed?(existing, attrs)
    ignored = %w[source_key source_row raw_json imported_at updated_at]
    attrs.any? do |key, value|
      next false if ignored.include?(key.to_s)

      existing_value = existing[key]
      comparable_value(existing_value) != comparable_value(value)
    end
  end
  private_class_method :object_changed?

  def comparable_value(value)
    value.nil? ? '' : value.to_s.strip
  end
  private_class_method :comparable_value

  def record_import(db, filename:, added:, updated:, skipped:, total:)
    db.execute(
      'INSERT INTO uute_imports(filename, imported_at, added_count, updated_count, skipped_count, total_rows) VALUES (?, ?, ?, ?, ?, ?)',
      [filename.to_s, Time.now.to_i, added.to_i, updated.to_i, skipped.to_i, total.to_i]
    )
  end

  def last_import(db)
    db.get_first_row('SELECT * FROM uute_imports ORDER BY imported_at DESC LIMIT 1')
  end

  def count(db, category: nil, query: nil)
    cat_where = category.to_s.empty? ? '' : "category = '#{category}' AND "
    if query.to_s.strip.empty?
      db.get_first_value("SELECT COUNT(*) FROM uute_objects WHERE #{cat_where}1=1").to_i
    else
      q = "%#{query.to_s.downcase}%"
      db.get_first_value("SELECT COUNT(*) FROM uute_objects WHERE #{cat_where}#{search_where}", [q, q, q, q, q, q, q]).to_i
    end
  end

  def list(db, category: nil, limit:, offset:, query: nil)
    cat_where = category.to_s.empty? ? '' : "category = '#{category}' AND "
    if query.to_s.strip.empty?
      db.execute(
        "SELECT * FROM uute_objects WHERE #{cat_where}1=1 ORDER BY COALESCE(NULLIF(TRIM(address), ''), name, '') LIMIT ? OFFSET ?",
        [limit, offset]
      )
    else
      q = "%#{query.to_s.downcase}%"
      db.execute(
        "SELECT * FROM uute_objects WHERE #{cat_where}#{search_where} ORDER BY COALESCE(NULLIF(TRIM(address), ''), name, '') LIMIT ? OFFSET ?",
        [q, q, q, q, q, q, q, limit, offset]
      )
    end
  end

  def all_for_category(db, category)
    db.execute("SELECT * FROM uute_objects WHERE category = ? ORDER BY COALESCE(NULLIF(TRIM(address), ''), name, '')", [category.to_s])
  end

  def find(db, id)
    db.get_first_row('SELECT * FROM uute_objects WHERE id = ?', [id.to_i])
  end

  def create(db, attrs)
    now = Time.now.to_i
    values = attrs.merge('imported_at' => now, 'updated_at' => now)
    keys = values.keys
    placeholders = (['?'] * keys.size).join(', ')
    db.execute(
      "INSERT INTO uute_objects (#{keys.join(', ')}) VALUES (#{placeholders})",
      values.values
    )
    db.last_insert_row_id
  end

  def create_or_update_link(db, uute_id:, contact_id:, status:, match_score: nil, match_reason: nil)
    now = Time.now.to_i
    db.execute(
      <<~SQL,
        INSERT INTO uute_contact_links(uute_id, contact_id, status, match_score, match_reason, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uute_id, contact_id) DO UPDATE SET
          status = excluded.status,
          match_score = excluded.match_score,
          match_reason = excluded.match_reason,
          updated_at = excluded.updated_at
      SQL
      [uute_id.to_i, contact_id.to_i, status.to_s, match_score, match_reason, now, now]
    )
    link_for_pair(db, uute_id: uute_id, contact_id: contact_id)
  end

  def link_for_pair(db, uute_id:, contact_id:)
    db.get_first_row(
      'SELECT * FROM uute_contact_links WHERE uute_id = ? AND contact_id = ?',
      [uute_id.to_i, contact_id.to_i]
    )
  end

  def links_for_uute(db, uute_id)
    db.execute('SELECT * FROM uute_contact_links WHERE uute_id = ? ORDER BY status, id', [uute_id.to_i])
  end

  def links_for_contact(db, contact_id)
    db.execute('SELECT * FROM uute_contact_links WHERE contact_id = ? ORDER BY status, id', [contact_id.to_i])
  end

  def delete_link(db, uute_id:, contact_id:)
    db.execute('DELETE FROM uute_contact_links WHERE uute_id = ? AND contact_id = ?', [uute_id.to_i, contact_id.to_i])
  end

  def get_act_counter(db, category:, kind:, year:)
    db.get_first_row(
      'SELECT * FROM uute_act_counters WHERE category = ? AND kind = ? AND year = ?',
      [category.to_s, kind.to_s, year.to_i]
    )
  end

  def set_act_counter(db, category:, kind:, year:, next_number:)
    db.execute(
      <<~SQL,
        INSERT INTO uute_act_counters(category, kind, year, next_number)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(category, kind, year) DO UPDATE SET next_number = excluded.next_number
      SQL
      [category.to_s, kind.to_s, year.to_i, next_number.to_i]
    )
  end

  def allocate_act_number(db, category:, kind:, year:)
    row = get_act_counter(db, category: category, kind: kind, year: year)
    number = row ? row['next_number'].to_i : 1
    set_act_counter(db, category: category, kind: kind, year: year, next_number: number + 1)
    number
  end

  def max_act_number_in_category(db, category:, kind:, year:, field:)
    col = case kind.to_s
          when 'act' then 'act_number'
          when 'primary' then 'act_primary_number'
          else 'act_periodic_number'
          end
    rows = db.execute(
      "SELECT #{col} AS num FROM uute_objects WHERE category = ? AND #{col} IS NOT NULL AND TRIM(#{col}) <> ''",
      [category.to_s]
    )
    max_num = 0
    rows.each do |row|
      n = row['num'].to_s.strip.to_i
      max_num = n if n > max_num
    end
    max_num
  end

  def search_where
    '(' \
      "lower_ru(COALESCE(name, '')) LIKE ? OR " \
      "lower_ru(COALESCE(address, '')) LIKE ? OR " \
      "lower_ru(COALESCE(contract_number, '')) LIKE ? OR " \
      "lower_ru(COALESCE(identifier, '')) LIKE ? OR " \
      "lower_ru(COALESCE(calculator_type, '')) LIKE ? OR " \
      "lower_ru(COALESCE(calculator_serial, '')) LIKE ? OR " \
      "lower_ru(COALESCE(service_org, '')) LIKE ?" \
    ')'
  end
  private_class_method :search_where
end
