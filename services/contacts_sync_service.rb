# frozen_string_literal: true

require 'fileutils'
require 'net/http'
require 'uri'
require 'roo'
require_relative '../storage/contacts_db'

module ContactsSyncService
  module_function

  CACHE_FILE = File.expand_path('../cache/contacts.xlsx', __dir__)

  TAB_MAPPING = {
    'УК и ТСЖ' => 'uk_tsj',
    'ГСПО' => 'gspo',
    'Прочие ФЛ' => 'phys',
    'Прочие ЮЛ' => 'legal',
    'Иглаково, коттеджи' => 'iglakovo'
  }.freeze

  def enabled?
    !document_id.empty?
  end

  def document_id
    ENV['CONTACTS_DOCUMENT_ID'].to_s.strip
  end

  def export_url
    "https://docs.google.com/spreadsheets/d/#{document_id}/export?format=xlsx"
  end

  def download(force: false)
    return false unless enabled?

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
      redirect = URI(res['location'])
      rh = Net::HTTP.new(redirect.host, redirect.port)
      rh.use_ssl = true
      rh.open_timeout = 30
      rh.read_timeout = 120
      res = rh.request(Net::HTTP::Get.new(redirect))
    end

    return false unless res.is_a?(Net::HTTPSuccess)

    File.binwrite(CACHE_FILE, res.body)
    true
  rescue => e
    warn "ContactsSyncService.download error: #{e.class}: #{e.message}"
    false
  end

  def sync(force: true)
    return [false, 'CONTACTS_DOCUMENT_ID не задан'] unless enabled?
    return [false, 'Не удалось скачать файл'] unless download(force: force)

    book = Roo::Excelx.new(CACHE_FILE)
    summary = {}
    ContactsDB.with_db do |db|
      TAB_MAPPING.each do |sheet_name, category|
        unless book.sheets.include?(sheet_name)
          summary[category] = { ok: false, count: 0, error: "Нет вкладки «#{sheet_name}»" }
          next
        end

        rows = parse_sheet(book, sheet_name, category)
        ContactsDB.replace_category(db, category, rows)
        summary[category] = { ok: true, count: rows.size, error: nil }
      end
      ContactsDB.set_meta(db, 'last_sync_at', Time.now.to_i.to_s)
    end
    [true, summary]
  rescue => e
    [false, "#{e.class}: #{e.message}"]
  end

  def parse_sheet(book, sheet_name, category)
    book.default_sheet = sheet_name
    last_row = book.last_row.to_i
    return [] if last_row < 1

    header_row, header_idx = find_header_row(book, last_row)
    return [] unless header_row

    column_map = build_column_map(header_row)
    return [] if column_map.empty?

    rows = []
    ((header_idx + 1)..last_row).each do |i|
      cells = safe_row(book, i)
      next if cells.all? { |c| c.to_s.strip.empty? }

      record = build_record(category, cells, column_map, i)
      rows << record if meaningful?(record)
    end
    rows
  end

  def safe_row(book, idx)
    book.row(idx).map { |c| normalize_cell(c) }
  rescue StandardError
    []
  end

  def normalize_cell(value)
    case value
    when nil then ''
    when Numeric
      if value.is_a?(Float) && value == value.to_i
        value.to_i.to_s
      else
        value.to_s
      end
    else
      value.to_s.strip
    end
  end

  HEADER_HINTS = %w[наимен адрес телефон руковод потребит владелец точка присоедин место нахождения юридическ объект].freeze

  def find_header_row(book, last_row)
    (1..[last_row, 6].min).each do |i|
      cells = safe_row(book, i).map { |c| c.to_s.downcase }
      hits = HEADER_HINTS.count { |hint| cells.any? { |c| c.include?(hint) } }
      return [safe_row(book, i), i] if hits >= 2
    end
    nil
  end

  def build_column_map(header_row)
    map = {}
    header_row.each_with_index do |cell, idx|
      key = normalize_header(cell)
      next if key.empty?

      map[key] ||= idx
    end
    map
  end

  def normalize_header(text)
    s = text.to_s.downcase.gsub(/[^[:alnum:]а-яё]+/, ' ').strip
    s
  end

  def column_value(cells, column_map, *header_keys)
    header_keys.each do |raw|
      key = normalize_header(raw)
      idx = column_map[key]
      next unless idx

      val = cells[idx].to_s.strip
      return val unless val.empty?
    end
    ''
  end

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

  def strip_html(text)
    s = text.to_s
    return s unless s.include?('<')

    s.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end

  PHONE_PATTERN = /(\+?\d[\d\s\-()]{7,}\d)/
  private_constant :PHONE_PATTERN

  def extract_phone_from_notes(notes)
    return '' if notes.to_s.strip.empty?

    match = notes.to_s.match(PHONE_PATTERN)
    match ? match[1].to_s.strip : ''
  end

  def build_record(category, cells, column_map, source_row)
    case category
    when 'uk_tsj'
      {
        name:        column_value_fuzzy(cells, column_map, 'наимен'),
        address:     column_value_fuzzy(cells, column_map, 'адрес'),
        manager:     column_value_fuzzy(cells, column_map, 'руковод'),
        phone:       column_value_fuzzy(cells, column_map, 'телефон'),
        connection_point: nil, consumer: nil, phone_alt: nil, notes: nil,
        source_row: source_row
      }

    when 'gspo'
      phone = ''
      column_map.each do |header, idx|
        next unless header.include?('телефон') && !header.include?('альтернат')

        v = cells[idx].to_s.strip
        if !v.empty?
          phone = v
          break
        end
      end
      phone_alt = column_value_fuzzy(cells, column_map, 'альтернат')
      {
        connection_point: column_value_fuzzy(cells, column_map, 'точка присоедин', 'присоедин'),
        name:             column_value_fuzzy(cells, column_map, 'наимен'),
        address:          column_value_fuzzy(cells, column_map, 'адрес'),
        consumer:         column_value_fuzzy(cells, column_map, 'потребит'),
        phone:            merge_phone_values(phone, phone_alt),
        phone_alt:        nil,
        manager: nil, notes: nil,
        identifier:       column_value_fuzzy(cells, column_map, 'идентификатор', 'uid'),
        metering_presence: column_value_fuzzy(cells, column_map, 'наличие пу', 'уу тэ', 'уутэ'),
        source_row: source_row
      }    when 'phys'
      responsible = column_value_fuzzy(cells, column_map, 'ответствен')
      notes = responsible.empty? ? column_value_fuzzy(cells, column_map, 'примечан') : responsible
      {
        consumer:  column_value_fuzzy(cells, column_map, 'потребит'),
        address:   column_value_fuzzy(cells, column_map, 'адрес'),
        phone:     column_value_fuzzy(cells, column_map, 'телефон'),
        phone_alt: extract_phone_from_notes(notes),
        notes:     notes,
        name: nil,
        manager: column_value_fuzzy(cells, column_map, 'руковод'),
        connection_point: nil,
        source_row: source_row
      }

    when 'legal'
      {
        name:    strip_html(column_value_fuzzy(cells, column_map, 'юридическ', 'наимен')),
        address: strip_html(column_value_fuzzy(cells, column_map, 'место нахожд', 'адрес')),
        phone:   column_value_fuzzy(cells, column_map, 'телефон'),
        manager: nil, consumer: nil, connection_point: nil, phone_alt: nil, notes: nil,
        source_row: source_row
      }

    when 'iglakovo'
      notice_phone = column_value_fuzzy(cells, column_map, 'телефон для уведом', 'уведом')
      checks_phone = column_value_fuzzy(cells, column_map, 'телефон общий', 'чек')
      {
        name:      column_value_fuzzy(cells, column_map, 'владел'),
        address:   column_value_fuzzy(cells, column_map, 'наимен', 'объект'),
        consumer:  column_value_fuzzy(cells, column_map, 'владел'),
        phone:     merge_phone_values(notice_phone, checks_phone),
        phone_alt: nil,
        manager: nil, connection_point: nil, notes: nil,
        source_row: source_row
      }

    else
      raise "unknown category: #{category}"
    end
  end

  def meaningful?(record)
    %i[name address consumer manager phone phone_alt connection_point].any? do |k|
      v = record[k].to_s.strip
      !v.empty?
    end
  end

  def merge_phone_values(*values)
    seen = {}
    parts = []

    values.each do |value|
      value.to_s.split(%r{[,;/\n]+}).each do |raw_part|
        part = raw_part.strip
        next if part.empty?

        key = normalize_phone_key(part)
        key = part.downcase if key.empty?
        next if seen[key]

        seen[key] = true
        parts << part
      end
    end

    parts.join(', ')
  end
  private_class_method :merge_phone_values

  def normalize_phone_key(value)
    digits = value.to_s.gsub(/\D+/, '')
    digits = "7#{digits[1..]}" if digits.length == 11 && digits.start_with?('8')
    digits
  end
  private_class_method :normalize_phone_key
end

