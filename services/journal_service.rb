# frozen_string_literal: true

require 'date'
require 'json'
require 'fileutils'
require_relative 'google_sheets_api'
require_relative '../storage/journal_db'

module JournalService
  module_function

  MONTHS_RU_NOM = %w[январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь].freeze
  WEEKDAY_LABELS = %w[Вс Пн Вт Ср Чт Пт Сб].freeze
  TIME_SLOTS = [
    '8:00-9:00',
    '9:00-10:00',
    '10:00-11:00',
    '11:00-12:00',
    '13:00-14:00',
    '14:00-15:00',
    '15:00-16:00',
    '16:00-17:00'
  ].freeze
  JOURNAL_PEOPLE_ORDER = [
    'Балашов А.А.',
    'Сапронов С.П.',
    'Горбунов А.А.',
    'Иванов К.В.',
    'Площинский В.В.',
    'Барыбин В.А',
    'Голоманский В.В.',
    'Иванов А.Н.',
    'Фадеев Д.А.',
    'Мишин А.Ю.',
    'Черкасов Д.О.',
    'Назаров А.Ю.'
  ].freeze
  # По пятницам последний слот не используется (рабочий день до 16:00).
  TIME_SLOTS_FRIDAY = TIME_SLOTS[0..-2].freeze
  HIDDEN_PEOPLE_COLUMN_PATTERNS = [
    /необходимо\s+п[оа]д?ключить\s+в\s+итп/i,
    /необходимо\s+ввести\s+приборы\s+учета/i,
    /надо\s+ввести\s+уутэ/i
  ].freeze
  HEADER_ROW = 1                # первая строка с именами
  DATE_COL = 0                  # A
  TIME_COL = 1                  # B
  FIRST_PERSON_COL = 2          # C+
  CACHE_TTL = 120               # сек — индекс листов / удалений
  WEEK_CACHE_TTL = 900            # сек (15 мин) — данные одной недели; ячейка после write patch-ится отдельно
  REFRESH_INTERVAL = 120        # сек — фоновое обновление
  DB_SYNC_TTL = 180             # сек — интервал обновления journal_db
  SCAN_RANGE = 'A1:Z250'
  SNAPSHOT_FILE = File.expand_path('../storage/journal_index.json', __dir__)

  @cache = nil
  @cache_at = 0
  @cache_mutex = Mutex.new

  @week_cache = {}              # monday_iso => { data:, at: }
  @week_cache_mutex = Mutex.new

  @refresh_thread_started = false
  @refresh_thread_mutex = Mutex.new
  @snapshot_mutex = Mutex.new

  def document_id
    ENV['SHEETS_DOCUMENT_ID'].to_s.strip
  end

  def enabled?
    !document_id.empty? && GoogleSheetsAPI.configured?
  end

  def api_available?
    enabled? || local_data_available?
  end

  def local_data_available?
    JournalDB.with_db { |db| JournalDB.week_starts(db).any? }
  rescue StandardError
    false
  end

  # Главный индекс: { by_date: { date_iso => { sheet, time_slots, people_cols, ... } },
  #                   sheet_meta: { name => { sheet_id, dates: {...}, people_cols, last_row, ... } } }
  #
  # Стратегия:
  # 1) Если кэша нет — пробуем загрузить снэпшот из storage/journal_index.json.
  # 2) Получаем актуальный список вкладок (один лёгкий запрос).
  # 3) Сканируем только новые вкладки или те, что относятся к текущему/будущему месяцам.
  #    Прошлые месяцы не трогаем — их данные не меняются.
  # 4) Сохраняем обновлённый индекс в снэпшот.
  def index_all(force: false)
    @cache_mutex.synchronize do
      return @cache if @cache && !force && (Time.now.to_i - @cache_at) < CACHE_TTL

      @cache ||= load_snapshot
      sheets = GoogleSheetsAPI.list_sheets(document_id)
      # Защита от временных сбоев Google API: если получили пустой список,
      # не считаем, что листы удалены, и не перетираем кэш/индекс.
      if sheets.empty?
        if @cache
          @cache_at = Time.now.to_i
          return @cache
        end
        raise 'Google Sheets returned empty sheets list'
      end
      sheets_by_name = sheets.each_with_object({}) { |s, h| h[s[:name]] = s }

      cached_meta = (@cache && @cache[:sheet_meta]) || {}
      today = Date.today
      current_my = [today.year, today.month]

      sheets_to_scan = sheets.select do |s|
        meta = cached_meta[s[:name]]
        next true if meta.nil?  # ещё не сканировали

        parsed = parse_sheet_month_year(s[:name])
        next false if parsed.nil?  # вкладки без даты в имени — сканируем только при первом старте
        (parsed <=> current_my) >= 0  # текущий и будущие месяцы — пере-сканируем
      end

      by_date = (@cache && @cache[:by_date].dup) || {}
      sheet_meta = (@cache && @cache[:sheet_meta].dup) || {}
      changed = false

      # 1. Удаляем из кэша вкладки, которых больше нет в Google.
      #    Делаем БЕЗУСЛОВНО — даже если новых сканировать не нужно,
      #    мы должны вычистить призраки от удалённых пользователем листов.
      deleted_names = sheet_meta.keys - sheets_by_name.keys
      if deleted_names.any?
        sheet_meta.delete_if { |n, _| deleted_names.include?(n) }
        by_date.delete_if { |_, v| deleted_names.include?(v[:sheet]) }
        changed = true
      end

      # 2. Сканируем только то, что нужно (новые + текущий/будущие месяцы).
      if sheets_to_scan.any?
        ranges = sheets_to_scan.map { |s| "#{s[:name]}!#{SCAN_RANGE}" }
        results = GoogleSheetsAPI.batch_get_ranges(document_id, ranges)

        # Перед мерджем чистим старые даты от листов, которые рескан-ятся.
        sheets_to_scan.each do |s|
          old = sheet_meta[s[:name]]
          next unless old

          (old[:dates] || {}).each_key { |iso| by_date.delete(iso) }
        end

        sheets_to_scan.each_with_index do |s, i|
          meta = scan_sheet_rows(s, results[i] || [])
          sheet_meta[s[:name]] = meta.merge(
            sheet_id: s[:id], total_rows: s[:rows], total_cols: s[:cols]
          )
          meta[:dates].each do |iso, data|
            by_date[iso] = data.merge(sheet: s[:name])
          end
        end

        changed = true
      end

      if changed
        @cache = { by_date: by_date, sheet_meta: sheet_meta, scanned_at: Time.now.to_i }
        save_snapshot
      end

      @cache_at = Time.now.to_i
      ensure_refresh_thread
      @cache
    end
  end

  def load_snapshot
    @snapshot_mutex.synchronize do
      return nil unless File.exist?(SNAPSHOT_FILE)

      raw = JSON.parse(File.read(SNAPSHOT_FILE, encoding: 'UTF-8'))
      raw = sanitize_utf8(raw)
      by_date = (raw['by_date'] || {}).each_with_object({}) do |(iso, v), h|
        h[iso] = symbolize_keys(v)
      end
      sheet_meta = (raw['sheet_meta'] || {}).each_with_object({}) do |(name, v), h|
        meta = symbolize_keys(v)
        meta[:dates] = (v['dates'] || {}).each_with_object({}) do |(iso, dv), dh|
          dh[iso] = symbolize_keys(dv)
        end
        h[name] = meta
      end
      { by_date: by_date, sheet_meta: sheet_meta, scanned_at: raw['scanned_at'].to_i }
    end
  rescue StandardError => e
    warn "JournalService.load_snapshot error: #{e.class}: #{e.message}"
    nil
  end
  private_class_method :load_snapshot

  def symbolize_keys(hash)
    hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
  end
  private_class_method :symbolize_keys

  def save_snapshot
    return unless @cache

    @snapshot_mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(SNAPSHOT_FILE))
      safe_cache = sanitize_utf8(@cache)
      json = JSON.generate(safe_cache, ascii_only: false)
      tmp = "#{SNAPSHOT_FILE}.tmp"
      File.open(tmp, 'wb') do |f|
        f.write(json.encode('UTF-8', invalid: :replace, undef: :replace, replace: ''))
        f.flush
        f.fsync
      end
      replace_file_with_retries(tmp, SNAPSHOT_FILE)
    end
  rescue StandardError => e
    warn "JournalService.save_snapshot error: #{e.class}: #{e.message}"
  end
  private_class_method :save_snapshot

  def replace_file_with_retries(src, dest, retries: 4)
    attempts = [retries, 1].max
    attempts.times do |i|
      begin
        FileUtils.mv(src, dest, force: true)
        return
      rescue Errno::EACCES
        raise if i >= attempts - 1

        sleep(0.05 * (i + 1))
      end
    end
  end
  private_class_method :replace_file_with_retries

  def sanitize_utf8(obj)
    case obj
    when String
      obj.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    when Array
      obj.map { |v| sanitize_utf8(v) }
    when Hash
      obj.each_with_object({}) do |(k, v), h|
        key = k.is_a?(String) ? sanitize_utf8(k) : k
        h[key] = sanitize_utf8(v)
      end
    else
      obj
    end
  end
  private_class_method :sanitize_utf8

  def ensure_refresh_thread
    @refresh_thread_mutex.synchronize do
      return if @refresh_thread_started

      @refresh_thread_started = true
      Thread.new do
        loop do
          sleep REFRESH_INTERVAL
          begin
            index_all(force: true)
            ensure_db_synced!(force: true)
            invalidate_old_week_cache
          rescue StandardError => e
            warn "JournalService background refresh error: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
  private_class_method :ensure_refresh_thread

  def invalidate_old_week_cache
    @week_cache_mutex.synchronize do
      cutoff = Time.now.to_i - WEEK_CACHE_TTL
      @week_cache.delete_if { |_, v| v[:at] < cutoff }
    end
  end
  private_class_method :invalidate_old_week_cache

  # Старая обёртка для совместимости (не используется в горячем пути).
  def scan_sheet(sheet_info)
    rows = GoogleSheetsAPI.read_range(document_id, sheet_info[:name], SCAN_RANGE)
    scan_sheet_rows(sheet_info, rows)
  end

  # Парсит уже прочитанные строки одной вкладки.
  def scan_sheet_rows(sheet_info, rows)
    rows = rows || []

    header = rows[HEADER_ROW - 1] || []
    people_cols = {}
    header.each_with_index do |cell, idx|
      next if idx < FIRST_PERSON_COL

      name_norm = cell.to_s.strip
      next if name_norm.empty?
      next if hidden_people_column?(name_norm)

      people_cols[name_norm] = idx
    end

    dates = {}
    current_iso = nil
    last_used_row = HEADER_ROW

    (HEADER_ROW..(rows.length - 1)).each do |i|
      row = rows[i] || []
      date_cell = (row[DATE_COL] || '').to_s.strip
      time_cell = (row[TIME_COL] || '').to_s.strip

      if !date_cell.empty?
        d = parse_date(date_cell)
        current_iso = d&.iso8601
      end

      next unless current_iso && !time_cell.empty?

      time_norm = normalize_time(time_cell)
      next unless time_norm

      dates[current_iso] ||= {
        date: current_iso,
        weekday: WEEKDAY_LABELS[Date.iso8601(current_iso).wday],
        time_slots: {},
        people_cols: people_cols
      }
      dates[current_iso][:time_slots][time_norm] = i + 1   # row 1-based
      last_used_row = i + 1
    end

    { dates: dates, people_cols: people_cols, last_row: last_used_row }
  end

  def normalize_time(text)
    s = text.to_s.gsub(/\s+/, '').gsub(/–/, '-').strip
    return s if TIME_SLOTS.include?(s)
    # допускаем варианты "9-10", "09:00-10:00" — приводим к каноническому
    m = s.match(/\A(\d{1,2})(?::00)?-(\d{1,2})(?::00)?\z/)
    return nil unless m

    canonical = "#{m[1].to_i}:00-#{m[2].to_i}:00"
    TIME_SLOTS.include?(canonical) ? canonical : nil
  end

  def parse_date(text)
    s = text.to_s.strip
    return nil if s.empty?

    %w[%d.%m.%Y %d/%m/%Y %m/%d/%Y %d-%m-%Y %Y-%m-%d %d.%m.%y].each do |fmt|
      d = Date.strptime(s, fmt) rescue nil
      next unless d
      return d if d.year >= 2000 && d.year <= 2100
    end
    nil
  end

  # Просто возвращаем все Mon-Fri недели, для которых в Google Sheets
  # есть хотя бы один день с данными. Сортируем хронологически.

  def weeks
    weeks_from_db
  end

  def weeks_from_db
    starts = JournalDB.with_db { |db| JournalDB.week_starts(db) }
    today = Date.today
    starts.map do |start_iso|
      monday = Date.iso8601(start_iso) rescue nil
      next unless monday
      friday = monday + 4
      {
        start: monday.iso8601,
        end: friday.iso8601,
        label: format_week_label(monday, friday),
        has_data: true,
        contains_today: today.between?(monday, friday)
      }
    end.compact
  rescue StandardError
    []
  end

  def search(query, limit: 50)
    q = safe_downcase(query)
    return [] if q.empty?

    db_rows = JournalDB.with_db { |db| JournalDB.search(db, q, limit: limit) }
    q_down = q.downcase
    filtered_rows = db_rows.select do |r|
      value = safe_downcase(r['value'])
      person = safe_downcase(r['person'])
      value.include?(q_down) || person.include?(q_down)
    end
    return filtered_rows.first(limit.to_i).map { |r|
      monday = Date.iso8601(r['week_start']) rescue nil
      friday = monday ? monday + 4 : nil
      {
        week_start: r['week_start'],
        week_label: monday ? format_week_label(monday, friday) : r['week_start'].to_s,
        date: r['date_iso'],
        time: r['time_slot'],
        person: r['person'],
        value: r['value'].to_s
      }
    } if filtered_rows.any?

    [] # нет данных в БД (например, первый холодный запуск до синка)
  end

  def safe_downcase(value)
    value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').downcase
  rescue StandardError
    value.to_s.downcase
  end
  private_class_method :safe_downcase

  def ensure_db_synced!(force: false)
    now = Time.now.to_i
    last_sync = JournalDB.with_db { |db| JournalDB.get_meta(db, 'last_sync_at').to_i }
    return if !force && last_sync > 0 && (now - last_sync) < DB_SYNC_TTL

    monday_set = {}
    index_all[:by_date].each_key do |iso|
      d = Date.iso8601(iso) rescue nil
      next unless d
      monday = d - ((d.wday - 1) % 7)
      monday_set[monday.iso8601] ||= monday
    end
    mondays = monday_set.values.sort
    # Синк только по рабочему окну: несколько последних недель + ближайшая вперед.
    # Глубокий архив не перечитываем — он практически не меняется.
    past_weeks = (ENV['JOURNAL_SYNC_PAST_WEEKS'] || '1').to_i
    future_weeks = (ENV['JOURNAL_SYNC_FUTURE_WEEKS'] || '4').to_i
    past_weeks = 4 if past_weeks <= 0
    future_weeks = 1 if future_weeks.negative?
    this_monday = Date.today - ((Date.today.wday - 1) % 7)
    min_monday = this_monday - (past_weeks * 7)
    max_monday = this_monday + (future_weeks * 7)
    mondays = mondays.select { |m| m >= min_monday && m <= max_monday }

    JournalDB.with_db do |db|
      mondays.each do |monday|
        week_start = monday.iso8601
        week = read_week_uncached(week_start)
        # Иногда Google на один запрос возвращает «пустую» неделю при сетевой
        # нестабильности. Делаем несколько попыток и берем самый «полный» вариант.
        best_week = week
        best_filled = filled_cells_count(week)
        if best_filled.zero?
          2.times do
            retry_week = read_week_uncached(week_start)
            retry_filled = filled_cells_count(retry_week)
            if retry_filled > best_filled
              best_week = retry_week
              best_filled = retry_filled
            end
            break if best_filled.positive?
          end
        end
        week = best_week
        unless valid_week_payload?(week)
          warn "JournalService.ensure_db_synced!: invalid week payload for #{week_start} (#{week.class})"
          next
        end
        rows = []
        values = week[:values].is_a?(Hash) ? week[:values] : {}
        days = week[:days].is_a?(Array) ? week[:days] : []
        values.each do |date_iso, by_time|
          next unless by_time.is_a?(Hash)

          weekday = days.find { |d| d[:date] == date_iso }&.dig(:weekday).to_s
          by_time.each do |time_slot, by_person|
            next unless by_person.is_a?(Hash)

            by_person.each do |person, value|
              rows << {
                date_iso: date_iso,
                weekday: weekday,
                time_slot: time_slot,
                person: person,
                value: value,
                sheet: ''
              }
            end
          end
        end
        # Защита от перетирания недели пустым набором при сбое чтения Google.
        next if rows.empty?
        new_filled = rows.count { |r| !r[:value].to_s.strip.empty? }
        if new_filled.zero? && monday <= Date.today
          existing_rows = JournalDB.week_rows(db, week_start)
          existing_filled = existing_rows.count { |r| !r['value'].to_s.strip.empty? }
          next if existing_filled.positive?
        end

        JournalDB.replace_week(db, week_start: week_start, rows: rows)
      end
      JournalDB.set_meta(db, 'last_sync_at', now.to_s)
    end
  end

  def valid_week_payload?(week)
    return false unless week.is_a?(Hash)

    week[:days].is_a?(Array) && week[:values].is_a?(Hash)
  end
  private_class_method :valid_week_payload?

  def filled_cells_count(week)
    return 0 unless week.is_a?(Hash)
    values = week[:values] || {}
    count = 0
    values.each_value do |by_time|
      by_time.each_value do |by_person|
        by_person.each_value do |v|
          count += 1 unless v.to_s.strip.empty?
        end
      end
    end
    count
  end
  private_class_method :filled_cells_count

  def default_weeks(count)
    today = Date.today
    monday = today - ((today.wday - 1) % 7)
    weeks_list = []
    (-2..(count - 3)).each do |offset|
      cur = monday + offset * 7
      friday = cur + 4
      weeks_list << {
        start: cur.iso8601,
        end: friday.iso8601,
        label: format_week_label(cur, friday),
        has_data: false,
        contains_today: today >= cur && today <= friday
      }
    end
    weeks_list
  end
  private_class_method :default_weeks

  def format_week_label(monday, friday)
    if monday.month == friday.month
      "#{monday.day}–#{friday.day} #{MONTHS_RU_NOM[monday.month - 1]} #{monday.year}"
    else
      "#{monday.day} #{MONTHS_RU_NOM[monday.month - 1]} – #{friday.day} #{MONTHS_RU_NOM[friday.month - 1]} #{friday.year}"
    end
  end
  private_class_method :format_week_label

  # Возвращает данные одной недели для UI. Кэшируется на 30 сек для быстрого UX.
  def read_week(monday_iso, force: false)
    read_week_from_db(monday_iso)
  end

  def read_week_from_db(monday_iso)
    monday = Date.iso8601(monday_iso)
    raise "monday_iso must be a Monday, got #{monday.wday}" if monday.wday != 1

    rows = JournalDB.with_db { |db| JournalDB.week_rows(db, monday_iso) }
    people = order_people(rows.map { |r| r['person'].to_s }.uniq)
    by_date = rows.group_by { |r| r['date_iso'].to_s }
    values = {}
    colors = {}
    days = []
    saturday_iso = (monday + 5).iso8601
    include_saturday = by_date.key?(saturday_iso)
    day_offsets = include_saturday ? (0..5).to_a : (0..4).to_a
    day_offsets.each do |offset|
      d = monday + offset
      iso = d.iso8601
      day_rows = by_date[iso] || []
      slots = day_rows.map { |r| r['time_slot'].to_s }.uniq
      slots = (d.wday == 5 || d.wday == 6) ? TIME_SLOTS_FRIDAY : TIME_SLOTS if slots.empty?
      slots = slots.sort_by { |t| TIME_SLOTS.index(t) || 99 }
      values[iso] ||= {}
      slots.each do |slot|
        values[iso][slot] ||= {}
        people.each { |p| values[iso][slot][p] = '' }
      end
      day_rows.each do |r|
        slot = r['time_slot'].to_s
        person = r['person'].to_s
        values[iso] ||= {}
        values[iso][slot] ||= {}
        values[iso][slot][person] = r['value'].to_s
        color = r['color'].to_s.strip
        colors["#{iso}|#{slot}|#{person}"] = color unless color.empty?
      end
      days << {
        date: iso,
        date_label: "#{d.day.to_s.rjust(2, '0')}.#{d.month.to_s.rjust(2, '0')}",
        weekday: WEEKDAY_LABELS[d.wday],
        sheet: nil,
        has_data: day_rows.any?,
        time_slots: slots
      }
    end

    {
      week: {
        start: monday.iso8601,
        end: (monday + (include_saturday ? 5 : 4)).iso8601,
        label: format_week_label(monday, monday + 4),
        contains_today: Date.today.between?(monday, monday + (include_saturday ? 5 : 4))
      },
      days: days,
      people: people,
      time_slots: TIME_SLOTS,
      values: values,
      colors: colors
    }
  end

  def read_week_uncached(monday_iso)
    monday = Date.iso8601(monday_iso)
    raise "monday_iso must be a Monday, got #{monday.wday}" if monday.wday != 1

    idx = index_all
    saturday_iso = (monday + 5).iso8601
    include_saturday = idx[:by_date].key?(saturday_iso)
    day_offsets = include_saturday ? (0..5).to_a : (0..4).to_a

    days = day_offsets.map do |offset|
      d = monday + offset
      iso = d.iso8601
      meta = idx[:by_date][iso]

      day_slots =
        if meta && meta[:time_slots].any?
          meta[:time_slots].keys.sort_by { |t| TIME_SLOTS.index(t) || 99 }
        else
          (d.wday == 5 || d.wday == 6) ? TIME_SLOTS_FRIDAY : TIME_SLOTS
        end

      {
        date: iso,
        date_label: "#{d.day.to_s.rjust(2, '0')}.#{d.month.to_s.rjust(2, '0')}",
        weekday: WEEKDAY_LABELS[d.wday],
        sheet: meta && meta[:sheet],
        has_data: !meta.nil?,
        time_slots: day_slots
      }
    end

    people = collect_people_for_week(idx, days)

    # Один батч-запрос на все диапазоны дней.
    ranges = []
    range_meta = []  # parallel array: { day, iso, sheet, first_row, time_rows, people_cols }
    days.each do |day|
      next unless day[:has_data]

      meta = idx[:by_date][day[:date]]
      sheet = meta[:sheet]
      time_rows = meta[:time_slots]
      next if time_rows.empty?

      first_row = time_rows.values.min
      last_row  = time_rows.values.max
      max_col_idx = (meta[:people_cols].values + [FIRST_PERSON_COL]).max
      a1 = "#{GoogleSheetsAPI.column_letter(0)}#{first_row}:#{GoogleSheetsAPI.column_letter(max_col_idx)}#{last_row}"
      ranges << "#{sheet}!#{a1}"
      range_meta << { iso: day[:date], first_row: first_row, time_rows: time_rows, people_cols: meta[:people_cols] }
    end

    range_data = GoogleSheetsAPI.batch_get_ranges(document_id, ranges) unless ranges.empty?
    range_data ||= []

    values = {}
    range_meta.each_with_index do |rm, i|
      data = range_data[i] || []
      day_values = {}
      rm[:time_rows].each do |time, row|
        local_idx = row - rm[:first_row]
        row_data = data[local_idx] || []
        per_person = {}
        people.each do |person|
          col = rm[:people_cols][person]
          per_person[person] = col ? (row_data[col] || '').to_s : ''
        end
        day_values[time] = per_person
      end
      values[rm[:iso]] = day_values
    end

    {
      week: {
        start: monday.iso8601,
        end: (monday + 4).iso8601,
        label: format_week_label(monday, monday + 4),
        contains_today: Date.today.between?(monday, monday + 4)
      },
      days: days,
      people: people,
      time_slots: TIME_SLOTS,
      values: values
    }
  end
  private_class_method :read_week_uncached

  def add_person_column(monday_iso, person_name)
    name = person_name.to_s.strip
    raise 'Название столбца пустое' if name.empty?
    raise 'Служебное название столбца запрещено' if hidden_people_column?(name)

    monday = Date.iso8601(monday_iso)
    sheet_name, sheet_meta = sheet_meta_for_week(monday)
    return { sheet: sheet_name, person: name, exists: true } if (sheet_meta[:people_cols] || {}).key?(name)

    last_col_idx = (sheet_meta[:people_cols].values + [FIRST_PERSON_COL - 1]).max
    new_col_idx = last_col_idx + 1
    a1 = GoogleSheetsAPI.cell_a1(HEADER_ROW - 1, new_col_idx)
    ok, err = GoogleSheetsAPI.write_cell(document_id, sheet_name, a1, name)
    raise err.to_s unless ok

    index_all(force: true)
    { sheet: sheet_name, person: name, exists: false }
  end

  def delete_person_column(monday_iso, person_name)
    name = person_name.to_s.strip
    raise 'Название столбца пустое' if name.empty?

    monday = Date.iso8601(monday_iso)
    sheet_name, sheet_meta = sheet_meta_for_week(monday)
    col = (sheet_meta[:people_cols] || {})[name]
    raise "Столбец «#{name}» не найден" unless col

    code, body = GoogleSheetsAPI.request(
      :post, document_id, ':batchUpdate', {},
      requests: [{
        deleteDimension: {
          range: {
            sheetId: sheet_meta[:sheet_id],
            dimension: 'COLUMNS',
            startIndex: col,
            endIndex: col + 1
          }
        }
      }]
    )
    unless code == 200
      msg = (JSON.parse(body).dig('error', 'message') rescue body.to_s[0, 300])
      raise "Не удалось удалить столбец: HTTP #{code}: #{msg}"
    end

    index_all(force: true)
    invalidate_week_cache(monday.iso8601)
    { sheet: sheet_name, person: name }
  end

  def rename_person_columns(monday_iso, mapping)
    monday = Date.iso8601(monday_iso)
    sheet_name, sheet_meta = sheet_meta_for_week(monday)
    people_cols = sheet_meta[:people_cols] || {}
    raise 'Нет столбцов для переименования' if people_cols.empty?

    renamed = []
    skipped = []

    mapping.to_h.each do |old_name_raw, new_name_raw|
      old_name = old_name_raw.to_s.strip
      new_name = new_name_raw.to_s.strip
      next if old_name.empty?
      if new_name.empty? || new_name == old_name
        skipped << old_name
        next
      end
      col = people_cols[old_name]
      unless col
        skipped << old_name
        next
      end
      if people_cols.key?(new_name)
        skipped << old_name
        next
      end
      raise 'Служебное название столбца запрещено' if hidden_people_column?(new_name)

      a1 = GoogleSheetsAPI.cell_a1(HEADER_ROW - 1, col)
      ok, err = GoogleSheetsAPI.write_cell(document_id, sheet_name, a1, new_name)
      raise err.to_s unless ok
      renamed << { from: old_name, to: new_name }
      people_cols.delete(old_name)
      people_cols[new_name] = col
    end

    index_all(force: true)
    invalidate_week_cache(monday.iso8601)
    { sheet: sheet_name, renamed: renamed, skipped: skipped }
  end

  def enable_saturday(monday_iso)
    monday = Date.iso8601(monday_iso)
    saturday = monday + 5
    saturday_iso = saturday.iso8601
    idx = index_all(force: true)
    return { already_exists: true, date: saturday_iso } if idx[:by_date].key?(saturday_iso)

    sheet_name, sheet_meta = sheet_meta_for_week(monday)
    last_col_idx = (sheet_meta[:people_cols].values + [TIME_COL]).max
    start_row = [sheet_meta[:last_row].to_i + 1, 2].max
    rows = TIME_SLOTS_FRIDAY.map.with_index do |time, i|
      row = Array.new(last_col_idx + 1, '')
      row[DATE_COL] = i.zero? ? saturday.strftime('%d.%m.%Y') : ''
      row[TIME_COL] = time
      row
    end
    end_row = start_row + rows.length - 1
    write_range = "#{sheet_name}!A#{start_row}:#{GoogleSheetsAPI.column_letter(last_col_idx)}#{end_row}"
    code, body = GoogleSheetsAPI.request(
      :put, document_id, "/values/#{URI.encode_www_form_component(write_range)}",
      { valueInputOption: 'USER_ENTERED' },
      { range: write_range, values: rows }
    )
    unless code == 200
      msg = (JSON.parse(body)['error']['message'] rescue body.to_s[0, 300])
      raise "Не удалось добавить субботу: HTTP #{code}: #{msg}"
    end

    index_all(force: true)
    sync_week_to_db!(monday.iso8601)
    invalidate_week_cache(monday.iso8601)
    { already_exists: false, date: saturday_iso }
  end

  def sync_week_to_db!(week_start_iso)
    monday = Date.iso8601(week_start_iso)
    week = read_week_uncached(monday.iso8601)
    return unless valid_week_payload?(week)

    rows = []
    values = week[:values].is_a?(Hash) ? week[:values] : {}
    days = week[:days].is_a?(Array) ? week[:days] : []
    values.each do |date_iso, by_time|
      next unless by_time.is_a?(Hash)

      weekday = days.find { |d| d[:date] == date_iso }&.dig(:weekday).to_s
      by_time.each do |time_slot, by_person|
        next unless by_person.is_a?(Hash)

        by_person.each do |person, value|
          rows << {
            date_iso: date_iso,
            weekday: weekday,
            time_slot: time_slot,
            person: person,
            value: value,
            sheet: ''
          }
        end
      end
    end
    JournalDB.with_db { |db| JournalDB.replace_week(db, week_start: monday.iso8601, rows: rows) } unless rows.empty?
  end
  private_class_method :sync_week_to_db!

  def sheet_meta_for_week(monday)
    idx = index_all(force: true)
    sheet_name = nil
    (0..6).each do |offset|
      iso = (monday + offset).iso8601
      entry = idx[:by_date][iso]
      next unless entry

      sheet_name = entry[:sheet]
      break
    end
    raise 'Неделя не найдена в Google Sheets' if sheet_name.to_s.empty?

    sheet_meta = idx[:sheet_meta][sheet_name]
    raise "Не найдены метаданные листа #{sheet_name}" unless sheet_meta

    [sheet_name, sheet_meta]
  end
  private_class_method :sheet_meta_for_week

  def invalidate_week_cache(date_iso)
    @week_cache_mutex.synchronize do
      monday_iso = (Date.iso8601(date_iso) - ((Date.iso8601(date_iso).wday - 1) % 7)).iso8601
      @week_cache.delete(monday_iso)
    end
  end
  private_class_method :invalidate_week_cache

  def collect_people_for_week(idx, days)
    sheets_in_week = days.map { |d| d[:sheet] }.compact.uniq
    sheets_to_use =
      if sheets_in_week.empty?
        idx[:sheet_meta].keys.first(1)
      else
        sheets_in_week
      end

    seen = []
    sheets_to_use.each do |name|
      meta = idx[:sheet_meta][name] || {}
      (meta[:people_cols] || {}).each_key do |person|
        next if hidden_people_column?(person)
        seen << person unless seen.include?(person)
      end
    end
    order_people(seen)
  end
  private_class_method :collect_people_for_week

  def normalize_person_for_order(name)
    name.to_s
        .downcase
        .gsub(/[^\p{L}\p{N}\s\.]/u, ' ')
        .gsub(/\s+/, ' ')
        .strip
  end
  private_class_method :normalize_person_for_order

  def order_people(people)
    list = Array(people).map(&:to_s).reject(&:empty?).uniq
    return list if list.empty?

    rank = JOURNAL_PEOPLE_ORDER.each_with_index.to_h do |name, i|
      [normalize_person_for_order(name), i]
    end

    list.sort_by do |name|
      norm = normalize_person_for_order(name)
      [rank.fetch(norm, 10_000), norm]
    end
  end
  private_class_method :order_people

  def hidden_people_column?(name)
    s = name.to_s.strip
    return true if s.empty?

    HIDDEN_PEOPLE_COLUMN_PATTERNS.any? { |pattern| s.match?(pattern) }
  end
  private_class_method :hidden_people_column?

  def cell_value(date_iso, time, person)
    cached_cell_value(date_iso, time, person)
  end

  def cached_cell_value(date_iso, time, person)
    monday_iso = (Date.iso8601(date_iso) - ((Date.iso8601(date_iso).wday - 1) % 7)).iso8601
    cached = @week_cache_mutex.synchronize { @week_cache[monday_iso]&.dig(:data) }
    if cached
      v = cached.dig(:values, date_iso, time, person)
      return v.to_s unless v.nil?
    end

    JournalDB.with_db do |db|
      stored = JournalDB.get_cell(db, date_iso: date_iso, time_slot: time, person: person)
      return stored unless stored.nil?
    end

    read_cell_from_google(date_iso, time, person)
  end
  private_class_method :cached_cell_value

  def read_cell_from_google(date_iso, time, person)
    meta = index_all[:by_date][date_iso]
    return '' unless meta

    row = meta[:time_slots][time]
    col = meta[:people_cols][person]
    return '' unless row && col

    read_cell_at(meta, row, col)
  end
  private_class_method :read_cell_from_google

  def read_cell_at(meta, row, col)
    a1 = GoogleSheetsAPI.cell_a1(row - 1, col)
    values = GoogleSheetsAPI.read_range(document_id, meta[:sheet], a1)
    values.dig(0, 0).to_s
  rescue StandardError
    ''
  end
  private_class_method :read_cell_at

  def patch_week_cache_cell(date_iso, time, person, value)
    monday_iso = (Date.iso8601(date_iso) - ((Date.iso8601(date_iso).wday - 1) % 7)).iso8601
    @week_cache_mutex.synchronize do
      entry = @week_cache[monday_iso]
      next unless entry && entry[:data]

      values = entry[:data][:values] ||= {}
      values[date_iso] ||= {}
      values[date_iso][time] ||= {}
      values[date_iso][time][person] = value.to_s
    end
  end
  private_class_method :patch_week_cache_cell

  # Записать одну ячейку по (date, time, person). Возвращает [ok, err, old_value].
  # old_value_hint — значение с клиента до правки (быстрее и точнее, чем повторное чтение).
  def write_cell(date_iso, time, person, value, old_value_hint: nil)
    idx = index_all
    meta = idx[:by_date][date_iso]
    if meta.nil?
      ok_week, _err_week = ensure_week_for_date(Date.iso8601(date_iso))
      unless ok_week
        old_value = old_value_hint.nil? ? db_cell_value(date_iso, time, person) : old_value_hint.to_s
        persist_cell_to_db(date_iso, time, person, value, '', old_value)
        patch_week_cache_cell(date_iso, time, person, value)
        return [true, nil, old_value.to_s]
      end

      idx = index_all(force: true)
      meta = idx[:by_date][date_iso]
      unless meta
        old_value = old_value_hint.nil? ? db_cell_value(date_iso, time, person) : old_value_hint.to_s
        persist_cell_to_db(date_iso, time, person, value, '', old_value)
        patch_week_cache_cell(date_iso, time, person, value)
        return [true, nil, old_value.to_s]
      end
    end

    row = meta[:time_slots][time]
    unless row
      old_value = old_value_hint.nil? ? db_cell_value(date_iso, time, person) : old_value_hint.to_s
      persist_cell_to_db(date_iso, time, person, value, meta[:sheet].to_s, old_value)
      patch_week_cache_cell(date_iso, time, person, value)
      return [true, nil, old_value.to_s]
    end

    col = meta[:people_cols][person]
    unless col
      old_value = old_value_hint.nil? ? db_cell_value(date_iso, time, person) : old_value_hint.to_s
      persist_cell_to_db(date_iso, time, person, value, meta[:sheet].to_s, old_value)
      patch_week_cache_cell(date_iso, time, person, value)
      return [true, nil, old_value.to_s]
    end

    old_value =
      if old_value_hint != nil
        old_value_hint.to_s
      else
        read_cell_at(meta, row, col)
      end

    a1 = GoogleSheetsAPI.cell_a1(row - 1, col)
    ok, err = GoogleSheetsAPI.write_cell(document_id, meta[:sheet], a1, value)
    if ok
      patch_week_cache_cell(date_iso, time, person, value)
      persist_cell_to_db(date_iso, time, person, value, meta[:sheet].to_s, old_value)
    end
    [ok, err, old_value]
  end

  #
  # ?????????, ??? ?????? ??? ????????? ? ??????? (?????? ? Google Sheets).
  def ensure_week_for_date(date)
    monday = date - ((date.wday - 1) % 7)
    return [true, nil] if (0..5).any? { |o| index_all[:by_date].key?((monday + o).iso8601) }
    return [true, nil] if (0..5).any? { |o| index_all(force: true)[:by_date].key?((monday + o).iso8601) }

    [false, 'This day is not created in Google Sheets yet ? click + Next week']
  end

  def db_cell_value(date_iso, time, person)
    JournalDB.with_db do |db|
      JournalDB.get_cell(db, date_iso: date_iso, time_slot: time, person: person).to_s
    end
  end
  private_class_method :db_cell_value

  def persist_cell_to_db(date_iso, time, person, value, sheet, old_value)
    monday = Date.iso8601(date_iso) - ((Date.iso8601(date_iso).wday - 1) % 7)
    JournalDB.with_db do |db|
      JournalDB.upsert_cell(
        db,
        week_start: monday.iso8601,
        date_iso: date_iso,
        weekday: WEEKDAY_LABELS[Date.iso8601(date_iso).wday],
        time_slot: time,
        person: person,
        value: value,
        sheet: sheet.to_s
      )
      if old_value.to_s != value.to_s
        JournalDB.add_event(
          db,
          date_iso: date_iso,
          time_slot: time,
          person: person,
          old_value: old_value.to_s,
          new_value: value.to_s
        )
      end
    end
  end
  private_class_method :persist_cell_to_db

  def write_cell_color(date_iso, time_slot, person, color)
    monday = Date.iso8601(date_iso) - ((Date.iso8601(date_iso).wday - 1) % 7)
    JournalDB.with_db do |db|
      JournalDB.upsert_cell_color(
        db,
        week_start: monday.iso8601,
        date_iso: date_iso,
        time_slot: time_slot,
        person: person,
        color: color
      )
    end
    patch_week_cache_color(date_iso, time_slot, person, color)
  end

  def cleanup_old_colors(older_than_days: 60)
    cutoff = (Date.today - older_than_days).iso8601
    JournalDB.with_db do |db|
      JournalDB.cleanup_old_colors(db, cutoff)
    end
  end

  def patch_week_cache_color(date_iso, time, person, color)
    return unless @week_cache.is_a?(Hash)
    key = "#{date_iso}|#{time}|#{person}"
    if color.to_s.strip.empty?
      @week_cache.delete(key)
    else
      @week_cache[key] = color.to_s.strip
    end
  end
  private_class_method :patch_week_cache_color

  #
  # ?????? ???? ????? ????????? ??????? ? Google Sheets.
  # Понедельник новой недели = понедельник_последней_известной_недели + 7.
  # Если данных нет вообще — берём текущий понедельник.
  # ??мя вкладки: "<Месяц> <Год> <N>", где N — следующий свободный номер
  # для этого месяца + года.
  # Возвращает [true, { start:, sheet: }] или [false, error_string].
  def create_next_week
    # Перечитываем Google Sheets перед расчётом — пользователь мог удалить
    # листы вручную, а кэш об этом не знает.
    idx = index_all(force: true)

    mondays = idx[:by_date].keys
                          .map { |iso| Date.iso8601(iso) rescue nil }
                          .compact
                          .map { |d| d - ((d.wday - 1) % 7) }
                          .uniq

    next_monday =
      if mondays.empty?
        today = Date.today
        today - ((today.wday - 1) % 7)
      else
        mondays.max + 7
      end

    # Шаблон — последняя по last_row вкладка с people_cols (т.е. валидной
    # шапкой). Берём именно последнюю чтобы получить актуальный список людей.
    template = idx[:sheet_meta]
                 .select { |_, m| m[:people_cols] && m[:people_cols].any? }
                 .max_by { |_, m| m[:last_row].to_i }
    return [false, 'Нет ни одной существующей вкладки для шаблона'] if template.nil?

    template_name, template_meta = template

    new_name = generate_unique_sheet_name(next_monday, idx[:sheet_meta].keys)

    code, body = GoogleSheetsAPI.request(
      :post, document_id, ':batchUpdate', {},
      requests: [{
        duplicateSheet: {
          sourceSheetId: template_meta[:sheet_id],
          insertSheetIndex: 0,
          newSheetName: new_name
        }
      }]
    )
    unless code == 200
      msg = (JSON.parse(body)['error']['message'] rescue body[0, 300])
      return [false, "Не смог создать вкладку: HTTP #{code}: #{msg}"]
    end

    new_sheet_id = JSON.parse(body).dig('replies', 0, 'duplicateSheet', 'properties', 'sheetId') rescue nil

    last_col_idx = template_meta[:people_cols].values.max
    last_col = GoogleSheetsAPI.column_letter(last_col_idx + 1)

    # 1) Чистим скопированные значения ниже шапки.
    clear_range = "#{new_name}!A2:#{last_col}1000"
    GoogleSheetsAPI.request(
      :post, document_id, "/values/#{URI.encode_www_form_component(clear_range)}:clear",
      {}, {}
    )

    # 2) Чистим всю заливку ниже шапки в белый, затем красим первые строки
    #    каждого дня (8-9 утра) в светло-серый. ?? главное — после последней
    #    строки данных (Пт 16:00) полностью сносим формат у "хвоста":
    #    рамки шаблона тянулись до ~50 строки и визуально выглядели как
    #    лишний пустой день (суббота).
    if new_sheet_id
      white = { red: 1.0, green: 1.0, blue: 1.0 }
      grey  = { red: 0.85, green: 0.85, blue: 0.85 }
      bg_field = 'userEnteredFormat.backgroundColor,userEnteredFormat.backgroundColorStyle'

      # 0-based индексы первых строк каждого дня + индекс первой строки ПОСЛЕ всех данных
      first_slot_rows = []
      cur = HEADER_ROW
      (0..4).each do |offset|
        first_slot_rows << cur
        cur += offset == 4 ? TIME_SLOTS_FRIDAY.size : TIME_SLOTS.size
      end
      data_end_row = cur  # 0-based индекс первой строки за пределами данных

      # Определяем фактическую ширину таблицы (по правой границе) — серить
      # будем ровно до этой колонки, иначе заливка «вылезает» в столбец M
      # за пределы рамок шаблона.
      table_end_col = last_col_idx + 2
      probe_code, probe_body = GoogleSheetsAPI.request(
        :get, document_id, '',
        ranges: "#{new_name}!A2:AZ2",
        fields: 'sheets(data(rowData(values(effectiveFormat(borders)))))',
        includeGridData: 'true'
      )
      if probe_code == 200
        cells = JSON.parse(probe_body).dig('sheets', 0, 'data', 0, 'rowData', 0, 'values') || []
        cells.each_with_index do |c, ci|
          borders = c.dig('effectiveFormat', 'borders') || {}
          table_end_col = ci + 1 unless borders.empty?
        end
      end

      requests = [
        # 1. Заливаем белым ВСЕ столбцы в области данных (шапка→Пт 16:00) —
        #    в т.ч. правее таблицы, чтобы убить «висящий» серый в столбце M.
        {
          repeatCell: {
            range: {
              sheetId: new_sheet_id,
              startRowIndex: HEADER_ROW,
              endRowIndex: data_end_row,
              startColumnIndex: 0
            },
            cell: { userEnteredFormat: { backgroundColor: white } },
            fields: bg_field
          }
        },
        # 2. Полностью сбрасываем формат (рамки + фон + любые шаблонные
        #    зелёные/жёлтые украшения) у ВСЕХ столбцов в строках после данных.
        {
          updateCells: {
            range: {
              sheetId: new_sheet_id,
              startRowIndex: data_end_row,
              endRowIndex: 1000,
              startColumnIndex: 0
            },
            fields: 'userEnteredFormat'
          }
        }
      ]

      # 3. Серая полоска для каждого первого слота дня — только в пределах рамок таблицы.
      first_slot_rows.each do |row_idx|
        requests << {
          repeatCell: {
            range: {
              sheetId: new_sheet_id,
              startRowIndex: row_idx,
              endRowIndex: row_idx + 1,
              startColumnIndex: 0,
              endColumnIndex: table_end_col
            },
            cell: { userEnteredFormat: { backgroundColor: grey } },
            fields: bg_field
          }
        }
      end

      GoogleSheetsAPI.request(:post, document_id, ':batchUpdate', {}, requests: requests)
    end

    # Заполняем новые строки: Пн-Чт по 8 слотов, Пт — 7 слотов (до 16:00).
    rows = []
    (0..4).each do |offset|
      d = next_monday + offset
      date_str = d.strftime('%d.%m.%Y')
      slots = offset == 4 ? TIME_SLOTS_FRIDAY : TIME_SLOTS
      slots.each_with_index do |time, ti|
        row = Array.new(last_col_idx + 1, '')
        row[DATE_COL] = ti.zero? ? date_str : ''
        row[TIME_COL] = time
        rows << row
      end
    end

    end_row = 1 + rows.size
    write_range = "#{new_name}!A2:#{GoogleSheetsAPI.column_letter(last_col_idx)}#{end_row}"
    code2, body2 = GoogleSheetsAPI.request(
      :put, document_id, "/values/#{URI.encode_www_form_component(write_range)}",
      { valueInputOption: 'USER_ENTERED' },
      { range: write_range, values: rows }
    )
    unless code2 == 200
      msg = (JSON.parse(body2)['error']['message'] rescue body2[0, 300])
      return [false, "Вкладка создана, но не заполнилась: HTTP #{code2}: #{msg}"]
    end

    index_all(force: true)
    invalidate_week_cache(next_monday.iso8601)
    [true, { start: next_monday.iso8601, sheet: new_name, template: template_name }]
  end

  def parse_sheet_month_year(name)
    s = name.to_s.downcase.strip
    m = s.match(/\A([а-яё]+)\s*\(?\s*(\d{4})?\s*\)?\s*\(?\s*\d*\s*\)?\z/)
    return nil unless m

    idx = MONTHS_RU_NOM.index(m[1])
    return nil unless idx

    year = m[2]&.to_i
    return nil unless year

    [year, idx + 1]
  end
  private_class_method :parse_sheet_month_year

  def generate_unique_sheet_name(monday, existing_names)
    month_idx = monday.month - 1
    base = "#{MONTHS_RU_NOM[month_idx].capitalize} #{monday.year}"
    n = 1
    while n < 100
      candidate = "#{base} #{n}"
      return candidate unless existing_names.include?(candidate)

      n += 1
    end
    # Крайне маловероятная ветка: вернём метку с timestamp
    "#{base} #{Time.now.to_i}"
  end
  private_class_method :generate_unique_sheet_name
end
