# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'net/http'
require 'uri'
require 'roo'
require_relative 'journal_service'

module SheetsService
  module_function

  CACHE_FILE = File.expand_path('../cache/sheets.xlsx', __dir__)
  META_FILE = File.expand_path('../cache/sheets_meta.json', __dir__)

  @parsed_mutex = Mutex.new
  @parsed = nil

  def local_journal_mode?
    (ENV['USE_LOCAL_JOURNAL_FOR_BOT'] || '1').to_s.strip == '1'
  end
  private_class_method :local_journal_mode?

  def local_week_payload
    weeks = JournalService.weeks
    return nil if weeks.nil? || weeks.empty?

    today = local_time.to_date
    target =
      weeks.find do |w|
        start_d = Date.iso8601(w[:start].to_s) rescue nil
        next false unless start_d
        today >= start_d && today <= (start_d + 6)
      end

    unless target
      past = weeks.select do |w|
        start_d = Date.iso8601(w[:start].to_s) rescue nil
        start_d && start_d <= today
      end
      target = past.last || weeks.last
    end

    return nil unless target && target[:start]
    JournalService.read_week(target[:start])
  rescue StandardError
    nil
  end
  private_class_method :local_week_payload

  def enabled?
    if local_journal_mode?
      return true if JournalService.enabled?
      return JournalDB.with_db { |db| JournalDB.week_starts(db).any? }
    end

    (ENV['SHEETS_ENABLED'] || '1').to_s.strip == '1' && !document_id.empty?
  end

  def document_id
    ENV['SHEETS_DOCUMENT_ID'].to_s.strip
  end

  def export_url
    "https://docs.google.com/spreadsheets/d/#{document_id}/export?format=xlsx"
  end

  def download(force: false)
    FileUtils.mkdir_p(File.dirname(CACHE_FILE))
    if !force && File.exist?(CACHE_FILE) && (Time.now - File.mtime(CACHE_FILE)) < 60
      return true
    end

    uri = URI(export_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 30
    http.read_timeout = 120

    res = http.request(Net::HTTP::Get.new(uri))

    if res.is_a?(Net::HTTPRedirection)
      redirect_uri = URI(res['location'])
      rh = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      rh.use_ssl = true
      rh.open_timeout = 30
      rh.read_timeout = 120
      res = rh.request(Net::HTTP::Get.new(redirect_uri))
    end

    return false unless res.is_a?(Net::HTTPSuccess)

    File.binwrite(CACHE_FILE, res.body)
    true
  rescue => e
    puts "SheetsService.download error: #{e.class}: #{e.message}"
    false
  end

  def cell_text(value)
    return '' if value.nil?

    value.to_s.dup.force_encoding('UTF-8').strip
  end
  private_class_method :cell_text

  def parse_date_cell(value)
    case value
    when Date then value
    when DateTime then value.to_date
    when Time then value.to_date
    when String
      s = value.strip
      return nil if s.empty?

      begin
        Date.parse(s)
      rescue
        nil
      end
    else
      nil
    end
  end
  private_class_method :parse_date_cell

  def excluded_names
    raw = ENV['SHEETS_EXCLUDE_NAMES'].to_s
    custom = raw.split(/\s*,\s*/).map { |s| s.to_s.dup.force_encoding('UTF-8').strip.downcase }.reject(&:empty?)
    defaults = [
      'необходимо потключить в итп',
      'необходимо ввести приборы учета'
    ]
    (defaults + custom).uniq
  end
  private_class_method :excluded_names

  def parse_week_tab(xlsx, sheet_name)
    xlsx.default_sheet = sheet_name
    rows = xlsx.last_row || 0
    cols = xlsx.last_column || 0
    return nil if rows < 2 || cols < 3

    time_marker = cell_text(xlsx.cell(1, 2)).downcase.gsub(/\s+/, '')
    return nil unless time_marker.include?('время') || time_marker == 'time'

    excluded = excluded_names
    people = []
    (3..cols).each do |c|
      name = cell_text(xlsx.cell(1, c))
      next if name.empty?
      next if excluded.include?(name.downcase.strip)

      people << { col: c, name: name }
    end
    return nil if people.empty?

    days = []
    current_date = nil
    current_day = nil

    (2..rows).each do |r|
      date_val = parse_date_cell(xlsx.cell(r, 1))
      if date_val
        current_date = date_val
        current_day = { date: current_date, slots: [] }
        days << current_day
      end

      next if current_day.nil?

      time = cell_text(xlsx.cell(r, 2))
      tasks_in_row = {}
      people.each do |p|
        text = cell_text(xlsx.cell(r, p[:col]))
        tasks_in_row[p[:name]] = text unless text.empty?
      end

      current_day[:slots] << { time: time, tasks: tasks_in_row }
    end

    { sheet_name: sheet_name, people: people.map { |p| p[:name] }, days: days }
  end
  private_class_method :parse_week_tab

  def find_current_week_tab(xlsx, today)
    candidates = xlsx.sheets.first(25)
    best = nil

    candidates.each do |name|
      parsed = parse_week_tab(xlsx, name) rescue nil
      next unless parsed && !parsed[:days].empty?

      dates = parsed[:days].map { |d| d[:date] }.compact
      next if dates.empty?

      min_d = dates.min
      max_d = dates.max
      if today >= min_d && today <= max_d
        return parsed
      end

      if today < min_d
        diff = (min_d - today).to_i
        best = parsed if best.nil? || diff < (best[:days].map { |d| d[:date] }.min - today).to_i
      end
    end

    best
  end
  private_class_method :find_current_week_tab

  def parse_current(force: false)
    if local_journal_mode?
      week = local_week_payload
      return nil unless week

      return {
        sheet_name: week.dig(:week, :label).to_s,
        people: week[:people] || [],
        days: (week[:days] || []).map do |d|
          {
            date: (Date.iso8601(d[:date]) rescue nil),
            slots: (d[:time_slots] || []).map do |slot|
              by_person = week.dig(:values, d[:date], slot) || {}
              { time: slot, tasks: by_person }
            end
          }
        end.compact
      }
    end

    @parsed_mutex.synchronize do
      return @parsed if @parsed && !force

      return nil unless File.exist?(CACHE_FILE)

      xlsx = Roo::Excelx.new(CACHE_FILE)
      today = Date.today
      parsed = find_current_week_tab(xlsx, today)
      @parsed = parsed
      parsed
    end
  end

  def refresh(force: false)
    if local_journal_mode?
      return nil unless enabled?
      JournalService.index_all(force: force)
      JournalService.ensure_db_synced!(force: force)
      return parse_current(force: true)
    end

    return nil unless enabled?

    ok = download(force: force)
    return nil unless ok

    parse_current(force: true)
  end

  def people
    parse_current&.dig(:people) || []
  end

  def available_dates
    (parse_current&.dig(:days) || []).map { |d| d[:date] }.compact.sort
  end

  def tasks_for(name, date)
    data = parse_current
    return [] unless data

    day = data[:days].find { |d| d[:date] == date }
    return [] unless day

    lookup_name = resolve_person_key(data[:people] || [], name.to_s)
    day[:slots].map do |slot|
      slot_tasks = slot[:tasks] || {}
      key = lookup_name || resolve_person_key(slot_tasks.keys, name.to_s)
      text = slot_tasks[key].to_s
      next nil if text.empty?

      { time: slot[:time], task: text }
    end.compact
  end

  def normalize_person_name(value)
    value.to_s
         .downcase
         .gsub(/[^\p{L}\p{N}\s\.]/u, ' ')
         .gsub(/\s+/, ' ')
         .strip
  end
  private_class_method :normalize_person_name

  def resolve_person_key(candidates, requested)
    req = normalize_person_name(requested)
    return nil if req.empty?
    exact = candidates.find { |c| normalize_person_name(c) == req }
    return exact if exact
    candidates.find { |c| normalize_person_name(c).start_with?(req) || req.start_with?(normalize_person_name(c)) }
  end
  private_class_method :resolve_person_key

  def sheet_name
    parse_current&.dig(:sheet_name)
  end

  def local_time(time = Time.now)
    offset = (ENV['SHEETS_TZ_OFFSET'] || '+07:00').to_s
    time.getlocal(offset)
  end

  def work_hour?(time = Time.now)
    from = (ENV['SHEETS_WORK_HOUR_FROM'] || '8').to_i
    to = (ENV['SHEETS_WORK_HOUR_TO'] || '17').to_i
    local = local_time(time)
    return false if local.saturday? || local.sunday?

    h = local.hour
    h >= from && h < to
  end

  def extract_address_from_task(text)
    s = text.to_s.dup.force_encoding('UTF-8')
    s = s.encode('UTF-8', invalid: :replace, undef: :replace) unless s.valid_encoding?
    s = s.strip
    return nil if s.empty?

    m = s.match(/\A((?:\d+\s+)?[а-яА-ЯёЁa-zA-Z][а-яА-ЯёЁa-zA-Z\s,\-\.]{1,40}?)[\s,]+(\d+)/)
    return nil unless m

    street = m[1].to_s.gsub(/[,\-\.]/, ' ').gsub(/\s+/, ' ').strip.downcase
    house = m[2].to_s
    return nil if street.length < 3

    "#{street} #{house}"
  end

  def refresh_interval_minutes
    return (ENV['SHEETS_REFRESH_WORK_MINUTES'] || '15').to_i if local_journal_mode?

    if work_hour?
      (ENV['SHEETS_REFRESH_WORK_MINUTES'] || '15').to_i
    else
      (ENV['SHEETS_REFRESH_OFFHOUR_MINUTES'] || '60').to_i
    end
  end
end
