# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'date'
require 'sqlite3'
require 'fileutils'
require 'spreadsheet'
require_relative '../storage/app_settings'

module BillingService
  module_function

  API_BASE = 'https://sheets.googleapis.com/v4/spreadsheets'
  OAUTH_URL = 'https://oauth2.googleapis.com/token'
  TIMEOUT = 30

  MONTHS_RU = %w[январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь].freeze

  # Колонки исходной Google-таблицы (0-based)
  COL_STATUS = 0
  COL_CONTRACT_NAME = 1
  COL_CONTRACT_NUMBER = 2
  COL_STREET = 3
  COL_HOUSE = 4
  COL_PURPOSE = 7
  COL_ADDRESS = 8
  COL_PURPOSE_2 = 9
  COL_RECONCILIATION_DATE = 10
  COL_POVERKA_NEXT = 11
  COL_COMMISSIONED = 12
  COL_SERIAL = 13
  COL_FINAL_DATE = 14
  COL_FINAL_VALUE = 15
  COL_CURRENT_DATE = 16
  COL_CURRENT_VALUE = 17
  COL_VOLUME_GVS = 18
  COL_SEAL_NUMBER = 23
  COL_SEAL_DATE = 24
  COL_METER_TYPE = 36

  @access_token = nil
  @access_token_expires_at = 0
  @token_mutex = Mutex.new
  @db_mutex = Mutex.new
  EXPORT_DIR = File.expand_path('../cache/exports', __dir__)
  EXPORT_COLUMNS = [
    ['Статус', 'status'],
    ['Наименование по договору', 'contract_name'],
    ['Номер договора', 'contract_number'],
    ['Улица', 'street'],
    ['Номер дома', 'house_number'],
    ['Назначение', 'purpose'],
    ['Назначение 2', 'purpose_2'],
    ['Адрес по договору', 'address'],
    ['Дата проведения сверки показаний', 'reconciliation_date'],
    ['Дата следующей поверки', 'poverka_next'],
    ['Дата ввода в эксплуатацию', 'commissioned'],
    ['Заводской номер счетчика', 'serial'],
    ['Дата передачи конечных показаний', 'final_date'],
    ['Конечные показания', 'final_value'],
    ['Дата передачи текущих показаний', 'current_date'],
    ['Текущие показания', 'current_value'],
    ['V ГВС', 'volume_gvs'],
    ['Номер пломбы', 'seal_number'],
    ['Дата опломбировки', 'seal_date'],
    ['Тип прибора', 'meter_type']
  ].freeze

  def db_path
    File.expand_path('../storage/billing.db', __dir__)
  end

  def enabled?
    (ENV['BILLING_ENABLED'] || '0').to_s.strip == '1'
  end

  def document_id
    ENV['BILLING_DOCUMENT_ID'].to_s.strip
  end

  def google_configured?
    !document_id.empty? &&
      !ENV['GOOGLE_OAUTH_CLIENT_ID'].to_s.strip.empty? &&
      !ENV['GOOGLE_OAUTH_REFRESH_TOKEN'].to_s.strip.empty?
  end

  def allowed_user_ids
    ENV['BILLING_ALLOWED_USER_IDS'].to_s.split(/\s*,\s*/).map(&:strip).reject(&:empty?)
  end

  def user_allowed?(user_id)
    ids = allowed_user_ids
    return false if ids.empty?
    ids.include?(user_id.to_s)
  end

  def month_creator_ids
    ENV['BILLING_MONTH_CREATOR_IDS'].to_s.split(/\s*,\s*/).map(&:strip).reject(&:empty?)
  end

  def user_can_create_month?(user_id)
    ids = month_creator_ids
    return false if ids.empty?
    ids.include?(user_id.to_s)
  end

  def month_creator_logins
    raw = AppSettings.get('billing_month_creator_logins')
    return [] unless raw.is_a?(Array)
    raw.map { |v| v.to_s.strip.downcase }.reject(&:empty?).uniq
  end

  def user_can_create_month_login?(login)
    allowed = month_creator_logins
    return false if allowed.empty?
    allowed.include?(login.to_s.strip.downcase)
  end

  def with_db
    @db_mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(db_path))
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      db.busy_timeout = 5_000
      ensure_schema(db)
      begin
        yield db
      ensure
        db.close
      end
    end
  end

  def ensure_schema(db)
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS billing_sheets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        sheet_index INTEGER NOT NULL DEFAULT 0,
        source_sheet_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS billing_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sheet_id INTEGER NOT NULL,
        row_num INTEGER NOT NULL,
        status TEXT,
        contract_name TEXT,
        contract_number TEXT,
        street TEXT,
        house_number TEXT,
        purpose TEXT,
        purpose_2 TEXT,
        address TEXT,
        reconciliation_date TEXT,
        poverka_next TEXT,
        commissioned TEXT,
        serial TEXT,
        final_date TEXT,
        final_value TEXT,
        current_date TEXT,
        current_value TEXT,
        volume_gvs TEXT,
        seal_number TEXT,
        seal_date TEXT,
        meter_type TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(sheet_id, row_num),
        FOREIGN KEY(sheet_id) REFERENCES billing_sheets(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_billing_records_sheet_row ON billing_records(sheet_id, row_num);
      CREATE INDEX IF NOT EXISTS idx_billing_records_sheet_active ON billing_records(sheet_id, active);
      CREATE INDEX IF NOT EXISTS idx_billing_records_sheet_name_addr ON billing_records(sheet_id, contract_name, address);
    SQL
    cols = db.execute('PRAGMA table_info(billing_records)').map { |r| r['name'] }
    db.execute('ALTER TABLE billing_records ADD COLUMN purpose_2 TEXT') unless cols.include?('purpose_2')
  end

  def ensure_local_data!
    has_data = with_db do |db|
      row = db.get_first_row('SELECT COUNT(*) AS c FROM billing_sheets')
      row['c'].to_i > 0
    end
    return if has_data
    return unless google_configured?

    import_all_from_google!
  rescue StandardError => e
    warn "BillingService ensure_local_data error: #{e.class}: #{e.message}"
  end

  def import_all_from_google!
    raise 'Google billing is not configured' unless google_configured?

    sheets = fetch_google_sheets
    now = Time.now.to_i
    with_db do |db|
      db.execute('BEGIN')
      db.execute('DELETE FROM billing_records')
      db.execute('DELETE FROM billing_sheets')
      sheets.each_with_index do |sheet, idx|
        db.execute(
          'INSERT INTO billing_sheets(name, sheet_index, source_sheet_id, created_at, updated_at) VALUES(?, ?, ?, ?, ?)',
          [sheet[:name], idx, sheet[:sheet_id], now, now]
        )
        local_sheet_id = db.last_insert_row_id
        rows = read_rows_google(sheet[:name])
        rows.each_with_index do |r, i|
          next if i.zero? # заголовок
          record = row_to_record_hash(r)
          db.execute(
            <<~SQL,
              INSERT INTO billing_records(
                sheet_id, row_num, status, contract_name, contract_number, street, house_number, purpose, purpose_2, address,
                reconciliation_date, poverka_next, commissioned, serial, final_date, final_value,
                current_date, current_value, volume_gvs, seal_number, seal_date, meter_type, active, created_at, updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            SQL
            [
              local_sheet_id, i + 1,
              record[:status], record[:contract_name], record[:contract_number], record[:street], record[:house_number], record[:purpose], record[:purpose_2], record[:address],
              record[:reconciliation_date], record[:poverka_next], record[:commissioned], record[:serial], record[:final_date], record[:final_value],
              record[:current_date], record[:current_value], record[:volume_gvs], record[:seal_number], record[:seal_date], record[:meter_type],
              active_row?(record[:status]) ? 1 : 0,
              now, now
            ]
          )
        end
      end
      db.execute('COMMIT')
    rescue StandardError
      db.execute('ROLLBACK') rescue nil
      raise
    end
    true
  end

  def current_sheet
    ensure_local_data!
    selected_sheet_id = AppSettings.get('billing_current_sheet_id').to_i
    with_db do |db|
      row = nil
      if selected_sheet_id.positive?
        row = db.get_first_row('SELECT id, name, sheet_index FROM billing_sheets WHERE id = ?', [selected_sheet_id])
      end
      row ||= db.get_first_row('SELECT id, name, sheet_index FROM billing_sheets ORDER BY sheet_index ASC, id ASC LIMIT 1')
      row ? { id: row['id'].to_i, name: row['name'].to_s } : nil
    end
  end

  def sheets
    ensure_local_data!
    current = current_sheet
    with_db do |db|
      rows = db.execute('SELECT id, name, sheet_index FROM billing_sheets')
      sort_sheet_rows(rows).map do |r|
        {
          id: r['id'].to_i,
          name: r['name'].to_s,
          current: current && current[:id] == r['id'].to_i
        }
      end
    end
  end

  def set_current_sheet(sheet_id: nil, name: nil)
    ensure_local_data!
    with_db do |db|
      target =
        if sheet_id
          db.get_first_row('SELECT id, name FROM billing_sheets WHERE id = ?', [sheet_id.to_i])
        elsif name
          db.get_first_row('SELECT id, name FROM billing_sheets WHERE name = ?', [name.to_s])
        end
      raise 'Вкладка не найдена' unless target

      AppSettings.set('billing_current_sheet_id', target['id'].to_i)
      { id: target['id'].to_i, name: target['name'].to_s }
    end
  end

  def list_objects(page: 0, page_size: 50, query: nil, status: 'active')
    ensure_local_data!
    sheet = current_sheet
    return { sheet: nil, page: 0, page_size: page_size, total: 0, records: [] } unless sheet

    q = normalize_query(query)
    tokens = split_tokens(q)
    page_i = [page.to_i, 0].max
    size_i = [[page_size.to_i, 1].max, 200].min

    with_db do |db|
      where = ['sheet_id = ?']
      args = [sheet[:id]]
      case status.to_s
      when 'active'
        where << 'active = 1'
      when 'inactive'
        where << 'active = 0'
      end
      rows = db.execute(
        "SELECT * FROM billing_records WHERE #{where.join(' AND ')} ORDER BY row_num ASC",
        args
      )
      filtered = if tokens.empty?
                   rows
                 else
                   rows.select do |r|
                     hay = "#{r['contract_name']} #{r['address']}".downcase
                     tokens.all? { |t| hay.include?(t) }
                   end
                 end

      total = filtered.size
      slice = filtered.slice(page_i * size_i, size_i) || []
      records = slice.map { |r| billing_record_to_api(r, sheet[:name]) }
      { sheet: sheet[:name], page: page_i, page_size: size_i, total: total, records: records }
    end
  end

  def find_objects(query, limit: 50, active_only: true)
    ensure_local_data!
    sheet = current_sheet
    return [] unless sheet
    tokens = split_tokens(normalize_query(query))
    return [] if tokens.empty?

    with_db do |db|
      where = ['sheet_id = ?']
      args = [sheet[:id]]
      where << 'active = 1' if active_only
      rows = db.execute(
        "SELECT row_num, contract_name, address FROM billing_records WHERE #{where.join(' AND ')} ORDER BY row_num ASC",
        args
      )
      rows
        .select do |r|
          hay = "#{r['contract_name']} #{r['address']}".downcase
          tokens.all? { |t| hay.include?(t) }
        end
        .first(limit.to_i)
        .map { |r| { row: r['row_num'].to_i, name: r['contract_name'].to_s, address: r['address'].to_s } }
    end
  end

  def object_details(row_num)
    ensure_local_data!
    sheet = current_sheet
    return nil unless sheet

    with_db do |db|
      row = db.get_first_row('SELECT * FROM billing_records WHERE sheet_id = ? AND row_num = ?', [sheet[:id], row_num.to_i])
      row ? billing_record_to_api(row, sheet[:name]) : nil
    end
  end

  def write_readings(row_num, value, date_str)
    ensure_local_data!
    sheet = current_sheet
    return [false, 'Нет активной вкладки'] unless sheet

    with_db do |db|
      row = db.get_first_row('SELECT * FROM billing_records WHERE sheet_id = ? AND row_num = ?', [sheet[:id], row_num.to_i])
      return [false, 'Объект не найден'] unless row

      final_v = parse_decimal(row['final_value'])
      current_v = parse_decimal(value)
      volume = if final_v && current_v
                 format_decimal(current_v - final_v)
               else
                 ''
               end
      now = Time.now.to_i
      db.execute(
        'UPDATE billing_records SET current_date = ?, current_value = ?, volume_gvs = ?, updated_at = ? WHERE id = ?',
        [date_str.to_s.strip, value.to_s.strip, volume, now, row['id']]
      )
      [true, nil]
    end
  end

  def update_object(row_num, attrs)
    ensure_local_data!
    sheet = current_sheet
    return [false, 'Нет активной вкладки'] unless sheet
    allowed = %w[status contract_name contract_number street house_number purpose purpose_2 address reconciliation_date poverka_next commissioned serial final_date final_value current_date current_value volume_gvs seal_number seal_date meter_type]
    updates = {}
    attrs.each do |k, v|
      key = k.to_s
      next unless allowed.include?(key)
      updates[key] = v.to_s.strip
    end
    return [false, 'Нет полей для обновления'] if updates.empty?

    with_db do |db|
      row = db.get_first_row('SELECT * FROM billing_records WHERE sheet_id = ? AND row_num = ?', [sheet[:id], row_num.to_i])
      return [false, 'Объект не найден'] unless row
      if updates.key?('current_value') || updates.key?('final_value')
        current = updates.key?('current_value') ? updates['current_value'] : row['current_value'].to_s
        final = updates.key?('final_value') ? updates['final_value'] : row['final_value'].to_s
        updates['volume_gvs'] = compute_volume(current, final)
      end
      if updates.key?('status')
        updates['active'] = active_row?(updates['status']) ? 1 : 0
      end
      updates['updated_at'] = Time.now.to_i
      sql = "UPDATE billing_records SET #{updates.keys.map { |k| "#{k} = ?" }.join(', ')} WHERE id = ?"
      db.execute(sql, updates.values + [row['id']])
      [true, nil]
    end
  end

  def create_object(attrs)
    ensure_local_data!
    sheet = current_sheet
    return [nil, 'Нет активной вкладки'] unless sheet
    with_db do |db|
      row_num = db.get_first_row('SELECT COALESCE(MAX(row_num), 1) AS v FROM billing_records WHERE sheet_id = ?', [sheet[:id]])['v'].to_i + 1
      now = Time.now.to_i
      payload = {
        status: attrs['status'].to_s.strip,
        contract_name: attrs['contract_name'].to_s.strip,
        contract_number: attrs['contract_number'].to_s.strip,
        street: attrs['street'].to_s.strip,
        house_number: attrs['house_number'].to_s.strip,
        purpose: attrs['purpose'].to_s.strip,
        purpose_2: attrs['purpose_2'].to_s.strip,
        address: attrs['address'].to_s.strip,
        reconciliation_date: attrs['reconciliation_date'].to_s.strip,
        poverka_next: attrs['poverka_next'].to_s.strip,
        commissioned: attrs['commissioned'].to_s.strip,
        serial: attrs['serial'].to_s.strip,
        final_date: attrs['final_date'].to_s.strip,
        final_value: attrs['final_value'].to_s.strip,
        current_date: attrs['current_date'].to_s.strip,
        current_value: attrs['current_value'].to_s.strip,
        volume_gvs: attrs['volume_gvs'].to_s.strip,
        seal_number: attrs['seal_number'].to_s.strip,
        seal_date: attrs['seal_date'].to_s.strip,
        meter_type: attrs['meter_type'].to_s.strip
      }
      payload[:volume_gvs] = compute_volume(payload[:current_value], payload[:final_value]) if payload[:volume_gvs].empty?
      active = active_row?(payload[:status]) ? 1 : 0
      db.execute(
        <<~SQL,
          INSERT INTO billing_records(
            sheet_id, row_num, status, contract_name, contract_number, street, house_number, purpose, purpose_2, address,
            reconciliation_date, poverka_next, commissioned, serial, final_date, final_value, current_date, current_value,
            volume_gvs, seal_number, seal_date, meter_type, active, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [
          sheet[:id], row_num, payload[:status], payload[:contract_name], payload[:contract_number], payload[:street], payload[:house_number], payload[:purpose], payload[:purpose_2], payload[:address],
          payload[:reconciliation_date], payload[:poverka_next], payload[:commissioned], payload[:serial], payload[:final_date], payload[:final_value], payload[:current_date], payload[:current_value],
          payload[:volume_gvs], payload[:seal_number], payload[:seal_date], payload[:meter_type], active, now, now
        ]
      )
      [object_details(row_num), nil]
    end
  end

  def create_next_month
    ensure_local_data!
    current = current_sheet
    return [nil, 'Не нашёл текущую вкладку'] unless current

    next_name = next_month_name(current[:name])
    return [nil, "Не смог вычислить следующий месяц из «#{current[:name]}»"] unless next_name

    with_db do |db|
      exists = db.get_first_row('SELECT id FROM billing_sheets WHERE name = ?', [next_name])
      return [nil, "Вкладка «#{next_name}» уже существует"] if exists

      now = Time.now.to_i
      # Как в Google-версии (insertSheetIndex: 0):
      # новый месяц должен становиться первым/текущим.
      db.execute('UPDATE billing_sheets SET sheet_index = sheet_index + 1, updated_at = ?', [now])
      new_idx = 0
      db.execute(
        'INSERT INTO billing_sheets(name, sheet_index, source_sheet_id, created_at, updated_at) VALUES(?, ?, NULL, ?, ?)',
        [next_name, new_idx, now, now]
      )
      new_sheet_id = db.last_insert_row_id
      AppSettings.set('billing_current_sheet_id', new_sheet_id.to_i)

      rows = db.execute('SELECT * FROM billing_records WHERE sheet_id = ? ORDER BY row_num ASC', [current[:id]])
      rows.each do |r|
        current_value = r['current_value'].to_s.strip
        final_date = current_value.empty? ? r['final_date'].to_s : r['current_date'].to_s
        final_value = current_value.empty? ? r['final_value'].to_s : current_value
        db.execute(
          <<~SQL,
            INSERT INTO billing_records(
              sheet_id, row_num, status, contract_name, contract_number, street, house_number, purpose, purpose_2, address,
              reconciliation_date, poverka_next, commissioned, serial, final_date, final_value,
              current_date, current_value, volume_gvs, seal_number, seal_date, meter_type, active, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            new_sheet_id, r['row_num'].to_i,
            r['status'], r['contract_name'], r['contract_number'], r['street'], r['house_number'], r['purpose'], r['purpose_2'], r['address'],
            r['reconciliation_date'], r['poverka_next'], r['commissioned'], r['serial'],
            final_date, final_value, '', '', '',
            r['seal_number'], r['seal_date'], r['meter_type'], r['active'].to_i,
            now, now
          ]
        )
      end
    end

    [next_name, nil]
  rescue StandardError => e
    [nil, e.message]
  end

  def delete_sheet(sheet_id)
    ensure_local_data!
    sid = sheet_id.to_i
    return [false, 'Некорректный id месяца'] if sid <= 0

    with_db do |db|
      target = db.get_first_row('SELECT id, name FROM billing_sheets WHERE id = ?', [sid])
      return [false, 'Месяц не найден'] unless target

      total = db.get_first_row('SELECT COUNT(*) AS c FROM billing_sheets')['c'].to_i
      return [false, 'Нельзя удалить последний месяц'] if total <= 1

      db.execute('BEGIN')
      begin
        db.execute('DELETE FROM billing_records WHERE sheet_id = ?', [sid])
        db.execute('DELETE FROM billing_sheets WHERE id = ?', [sid])
        db.execute('UPDATE billing_sheets SET sheet_index = sheet_index - 1 WHERE sheet_index > 0')

        selected_sheet_id = AppSettings.get('billing_current_sheet_id').to_i
        if selected_sheet_id == sid
          next_row = db.get_first_row('SELECT id FROM billing_sheets ORDER BY sheet_index ASC, id ASC LIMIT 1')
          AppSettings.set('billing_current_sheet_id', next_row ? next_row['id'].to_i : 0)
        end

        db.execute('COMMIT')
      rescue StandardError
        db.execute('ROLLBACK') rescue nil
        raise
      end

      [true, target['name'].to_s]
    end
  end

  def sheet_names
    ensure_local_data!
    with_db do |db|
      rows = db.execute('SELECT id, name, sheet_index FROM billing_sheets')
      sort_sheet_rows(rows).map { |r| r['name'].to_s }
    end
  end

  def parse_sheet_month(name)
    s = name.to_s.strip.downcase
    m = s.match(/\A([а-яё]+)\s+(\d{4})\z/)
    return nil unless m
    idx = MONTHS_RU.index(m[1])
    return nil unless idx
    { month_idx: idx, year: m[2].to_i }
  end

  def sort_sheet_rows(rows)
    Array(rows).sort_by do |r|
      parsed = parse_sheet_month(r['name'].to_s)
      if parsed
        # Новые месяцы сверху: 2026-05, 2026-04, ...
        [-parsed[:year].to_i, -parsed[:month_idx].to_i]
      else
        # fallback для нестандартных имен
        [0, r['sheet_index'].to_i, r['id'].to_i]
      end
    end
  end
  private_class_method :sort_sheet_rows

  def next_month_name(current_name)
    parsed = parse_sheet_month(current_name)
    return nil unless parsed
    if parsed[:month_idx] == 11
      "#{MONTHS_RU[0].capitalize} #{parsed[:year] + 1}"
    else
      "#{MONTHS_RU[parsed[:month_idx] + 1].capitalize} #{parsed[:year]}"
    end
  end

  def local_today
    offset = (ENV['SHEETS_TZ_OFFSET'] || '+07:00').to_s
    Time.now.getlocal(offset).to_date
  end

  def format_date_ru(date)
    date.strftime('%d.%m.%Y')
  end

  def parse_flexible_date(s)
    text = s.to_s.strip
    return nil if text.empty?
    ['%d.%m.%Y', '%d.%m.%y', '%m/%d/%Y', '%d/%m/%Y', '%Y-%m-%d', '%d-%m-%Y'].each do |fmt|
      begin
        d = Date.strptime(text, fmt)
        return d if d.year >= 2000 && d.year <= 2099
      rescue ArgumentError
        next
      end
    end
    nil
  end

  def end_of_month_for(name)
    parsed = parse_sheet_month(name)
    return nil unless parsed
    Date.new(parsed[:year], parsed[:month_idx] + 1, -1)
  end

  def expiring_poverki(within_days: nil, until_date: nil)
    ensure_local_data!
    sheet = current_sheet
    return [] unless sheet
    today = local_today
    horizon = until_date || (today + (within_days || 30))

    with_db do |db|
      rows = db.execute('SELECT row_num, contract_name, address, serial, poverka_next, active FROM billing_records WHERE sheet_id = ?', [sheet[:id]])
      rows.each_with_object([]) do |r, out|
        next if r['active'].to_i == 0
        d = parse_flexible_date(r['poverka_next'])
        next unless d
        next if d < today || d > horizon
        out << {
          row: r['row_num'].to_i,
          name: r['contract_name'].to_s,
          address: r['address'].to_s,
          serial: r['serial'].to_s,
          poverka_next: r['poverka_next'].to_s,
          poverka_date: d,
          days_left: (d - today).to_i
        }
      end.sort_by { |x| x[:days_left] }
    end
  end

  def parse_date_input(text)
    s = text.to_s.strip
    return nil if s.empty?
    return local_today if s.downcase == 'сегодня'
    ['%d.%m.%Y', '%d.%m.%y', '%d/%m/%Y', '%d/%m/%y', '%Y-%m-%d', '%d-%m-%Y', '%d.%m'].each do |fmt|
      begin
        d = Date.strptime(s, fmt)
        d = Date.new(local_today.year, d.month, d.day) if fmt == '%d.%m'
        return d
      rescue ArgumentError
        next
      end
    end
    nil
  end

  def export_current_sheet(status: 'all')
    ensure_local_data!
    sheet = current_sheet
    raise 'Нет активной вкладки' unless sheet
    rows = with_db do |db|
      where = ['sheet_id = ?']
      args = [sheet[:id]]
      case status.to_s
      when 'active'
        where << 'active = 1'
      when 'inactive'
        where << 'active = 0'
      end
      db.execute("SELECT * FROM billing_records WHERE #{where.join(' AND ')} ORDER BY row_num ASC", args)
    end

    FileUtils.mkdir_p(EXPORT_DIR)
    suffix = status.to_s == 'all' ? 'all' : status.to_s
    filename = "billing_#{sheet[:name].gsub(/\s+/, '_')}_#{suffix}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.xls"
    path = File.join(EXPORT_DIR, filename)

    book = Spreadsheet::Workbook.new
    ws = book.create_worksheet(name: sheet[:name][0, 31])
    header_format = Spreadsheet::Format.new(weight: :bold)

    EXPORT_COLUMNS.each_with_index do |(title, _key), col|
      ws[0, col] = title
      ws.row(0).set_format(col, header_format)
      ws.column(col).width = [title.length + 3, 16].max
    end

    rows.each_with_index do |row, i|
      EXPORT_COLUMNS.each_with_index do |(_title, key), col|
        ws[i + 1, col] = row[key].to_s
      end
    end
    book.write(path)
    [path, filename]
  end

  # ----- Google read helpers (только импорт) -----
  def access_token
    @token_mutex.synchronize do
      if @access_token.nil? || Time.now.to_i >= @access_token_expires_at - 60
        refresh_access_token!
      end
      @access_token
    end
  end

  def refresh_access_token!
    uri = URI(OAUTH_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(
      'refresh_token' => ENV['GOOGLE_OAUTH_REFRESH_TOKEN'],
      'client_id' => ENV['GOOGLE_OAUTH_CLIENT_ID'],
      'client_secret' => ENV['GOOGLE_OAUTH_CLIENT_SECRET'],
      'grant_type' => 'refresh_token'
    )
    res = http.request(req)
    data = JSON.parse(res.body) rescue {}
    raise "Token refresh failed: HTTP #{res.code}" unless data['access_token']
    @access_token = data['access_token']
    @access_token_expires_at = Time.now.to_i + (data['expires_in'] || 3600).to_i
  end
  private_class_method :refresh_access_token!

  def api_request(method, path, params = {}, body = nil)
    uri = URI("#{API_BASE}/#{document_id}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    req = case method
          when :get then Net::HTTP::Get.new(uri)
          when :post then Net::HTTP::Post.new(uri)
          else Net::HTTP::Get.new(uri)
          end
    req['Authorization'] = "Bearer #{access_token}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body) if body
    res = http.request(req)
    [res.code.to_i, res.body.to_s]
  end
  private_class_method :api_request

  def fetch_google_sheets
    code, body = api_request(:get, '', fields: 'sheets.properties.title,sheets.properties.sheetId')
    raise "Google sheets read failed: #{code}" unless code == 200
    data = JSON.parse(body) rescue {}
    Array(data['sheets']).map do |s|
      p = s['properties'] || {}
      { name: p['title'].to_s, sheet_id: p['sheetId'].to_i }
    end
  end
  private_class_method :fetch_google_sheets

  def read_rows_google(sheet_name, range_suffix = 'A:AZ')
    path = "/values/#{URI.encode_www_form_component(sheet_name)}!#{range_suffix}"
    code, body = api_request(:get, path)
    return [] unless code == 200
    JSON.parse(body)['values'] || []
  end
  private_class_method :read_rows_google

  # ----- mappers -----
  def row_to_record_hash(r)
    final_value = clean(r[COL_FINAL_VALUE])
    current_value = clean(r[COL_CURRENT_VALUE])
    volume = clean(r[COL_VOLUME_GVS])
    volume = compute_volume(current_value, final_value) if volume.empty?
    {
      status: clean(r[COL_STATUS]),
      contract_name: clean(r[COL_CONTRACT_NAME]),
      contract_number: clean(r[COL_CONTRACT_NUMBER]),
      street: clean(r[COL_STREET]),
      house_number: clean(r[COL_HOUSE]),
      purpose: clean(r[COL_PURPOSE]),
      purpose_2: clean(r[COL_PURPOSE_2]),
      address: clean(r[COL_ADDRESS]),
      reconciliation_date: clean(r[COL_RECONCILIATION_DATE]),
      poverka_next: clean(r[COL_POVERKA_NEXT]),
      commissioned: clean(r[COL_COMMISSIONED]),
      serial: clean(r[COL_SERIAL]),
      final_date: clean(r[COL_FINAL_DATE]),
      final_value: final_value,
      current_date: clean(r[COL_CURRENT_DATE]),
      current_value: current_value,
      volume_gvs: volume,
      seal_number: clean(r[COL_SEAL_NUMBER]),
      seal_date: clean(r[COL_SEAL_DATE]),
      meter_type: clean(r[COL_METER_TYPE])
    }
  end
  private_class_method :row_to_record_hash

  def billing_record_to_api(r, sheet_name)
    {
      row: r['row_num'].to_i,
      sheet: sheet_name.to_s,
      status: r['status'].to_s,
      contract_name: r['contract_name'].to_s,
      contract_number: r['contract_number'].to_s,
      street: r['street'].to_s,
      house_number: r['house_number'].to_s,
      purpose: r['purpose'].to_s,
      purpose_2: r['purpose_2'].to_s,
      name: r['contract_name'].to_s,
      address: r['address'].to_s,
      reconciliation_date: r['reconciliation_date'].to_s,
      commissioned: r['commissioned'].to_s,
      poverka_next: r['poverka_next'].to_s,
      serial: r['serial'].to_s,
      final_date: r['final_date'].to_s,
      final_value: r['final_value'].to_s,
      current_date: r['current_date'].to_s,
      current_value: r['current_value'].to_s,
      volume_gvs: r['volume_gvs'].to_s,
      seal_number: r['seal_number'].to_s,
      seal_date: r['seal_date'].to_s,
      meter_type: r['meter_type'].to_s
    }
  end
  private_class_method :billing_record_to_api

  def normalize_query(query)
    query.to_s.downcase.strip
  end
  private_class_method :normalize_query

  def split_tokens(query)
    query.to_s.split(/[\s,.\-–—;\/]+/).reject(&:empty?)
  end
  private_class_method :split_tokens

  def clean(v)
    v.to_s.strip
  end
  private_class_method :clean

  def parse_decimal(text)
    s = text.to_s.strip.tr(',', '.')
    return nil if s.empty?
    Float(s)
  rescue StandardError
    nil
  end
  private_class_method :parse_decimal

  def format_decimal(number)
    s = format('%.3f', number.to_f)
    s.sub(/\.?0+\z/, '')
  end
  private_class_method :format_decimal

  def compute_volume(current_value, final_value)
    c = parse_decimal(current_value)
    f = parse_decimal(final_value)
    return '' unless c && f
    format_decimal(c - f)
  end
  private_class_method :compute_volume

  def active_row?(status)
    s = status.to_s.downcase
    !s.include?('неактив')
  end
  private_class_method :active_row?
end
