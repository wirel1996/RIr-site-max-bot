# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'time'
require 'date'
require_relative 'arshin_type_priority'

module ArshinService
  module_function

  def enabled?
    (ENV['ARSHIN_ENABLED'] || '1').to_s.strip == '1'
  end

  def api_base_url
    ENV.fetch('ARSHIN_API_BASE_URL', 'https://fgis.gost.ru/fundmetrology/eapi/vri')
  end

  def timeout_seconds
    (ENV['ARSHIN_TIMEOUT_SECONDS'] || '15').to_i
  end

  def result_limit
    (ENV['ARSHIN_RESULT_LIMIT'] || '5').to_i
  end

  def debug?
    (ENV['ARSHIN_DEBUG'] || '0').to_s.strip == '1'
  end

  def log_path
    File.expand_path((ENV['ARSHIN_LOG_PATH'] || '../log/arshin.log').to_s, __dir__)
  end

  def type_api_keys
    keys = (ENV['ARSHIN_TYPE_API_KEYS'] || 'mit_notation')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
    keys.empty? ? ['mit_notation'] : keys
  end

  def mer_org_title
    ENV.fetch('ARSHIN_MER_ORG_TITLE', 'ООО "МЭР"')
  end

  def org_titles
    env = ENV['ARSHIN_ORG_TITLES'].to_s.strip
    return env.split('|').map(&:strip).reject(&:empty?) unless env.empty?

    [
      mer_org_title,
      'ООО "АРТЕБ-РЕСУРС"',
      'ООО "ЦСО"',
      'ФБУ "ТОМСКИЙ ЦСМ"',
      'ФГУП "ВНИИМ ИМ. Д.И.МЕНДЕЛЕЕВА"'
    ].map(&:strip).reject(&:empty?).uniq
  end

  def auto_org_titles
    org_titles.reject { |v| v.to_s.include?('МЕНДЕЛЕЕВА') }
  end

  def allowed_years
    (ENV['ARSHIN_ALLOWED_YEARS'] || '2026,2025,2024,2023,2022,2021')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
  end

  def log(message)
    return unless debug?

    FileUtils.mkdir_p(File.dirname(log_path))
    File.open(log_path, 'a', encoding: 'utf-8') do |f|
      f.puts "[#{Time.now.iso8601}] #{message}"
    end
  rescue => e
    puts "arshin_log error: #{e.class}: #{e.message}"
  end

  def utf8_text(value)
    text = value.to_s.dup
    text = text.force_encoding('UTF-8')
    return text if text.valid_encoding?

    value.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
  rescue StandardError
    value.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
  end

  def max_arshin_year_keyboard
    rows = allowed_years.each_slice(3).map do |slice|
      slice.map { |year| { text: year, payload: year } }
    end
    rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
    max_inline_keyboard(rows)
  end

  def max_arshin_org_keyboard
    rows = org_titles.map { |title| [{ text: title, payload: title }] }
    rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
    max_inline_keyboard(rows)
  end

  def arshin_form_normalize(form)
    normalized = {
      'org_title' => nil,
      'year' => nil,
      'mi_number' => nil,
      'mit_notation' => nil
    }

    (form || {}).each do |key, value|
      normalized_key = key.to_s
      next unless normalized.key?(normalized_key)

      text_value = value.to_s.strip
      normalized[normalized_key] = text_value.empty? ? nil : text_value
    end

    normalized
  end

  def max_arshin_form_keyboard(form = {}, arshin_items_count: 0)
    f = arshin_form_normalize(form)
    rows = [
      [{ text: "Поверитель (организация): #{arshin_form_value(f['org_title'])}", payload: 'arshin:set:org' }],
      [{ text: "Год поверки: #{arshin_form_year_value(f['year'])}", payload: 'arshin:set:year' }],
      [{ text: "Номер прибора: #{arshin_form_value(f['mi_number'])}", payload: 'arshin:set:number' }],
      [{ text: "Тип/обозн. прибора: #{arshin_form_value(f['mit_notation'])}", payload: 'arshin:set:notation' }],
      [{ text: 'Найти прибор', payload: 'arshin:find' }]
    ]
    case arshin_items_count
    when 0
      # ни одной подходящей записи — кнопки PDF нет
    when 1
      rows << [{ text: '📄 Положить PDF в папку на Я.Диск', payload: 'arshin:put_snap:0' }]
    else
      arshin_items_count.times.each_slice(3) do |slice|
        rows << slice.map { |i| { text: "📄 PDF по №#{i + 1}", payload: "arshin:put_snap:#{i}" } }
      end
    end
    rows << [{ text: 'Очистить', payload: 'arshin:clear' }]
    rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
    max_inline_keyboard(rows)
  end

  def registry_link_for_serial(serial, year: nil)
    s = serial.to_s.strip
    return 'https://fgis.gost.ru/fundmetrology/cm/results' if s.empty?

    params = { 'search' => s }
    params['activeYear'] = year.to_s if year && !year.to_s.strip.empty?
    "https://fgis.gost.ru/fundmetrology/cm/results?#{URI.encode_www_form(params)}"
  end

  def registry_link_for_item(item)
    id = (item['vri_id'] || item['id']).to_s.strip
    return '' if id.empty?

    "https://fgis.gost.ru/fundmetrology/cm/results/#{URI.encode_www_form_component(id)}"
  end

  def with_registry_links(items)
    Array(items).map do |item|
      next item unless item.is_a?(Hash)

      link = registry_link_for_item(item)
      link.empty? ? item : item.merge('registry_url' => link)
    end
  end

  def shorten_url(url)
    uri = URI("https://clck.ru/--?url=#{URI.encode_www_form_component(url.to_s)}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    res = http.request(Net::HTTP::Get.new(uri))
    return url unless res.is_a?(Net::HTTPSuccess)

    short = res.body.to_s.strip
    short.start_with?('http') ? short : url
  rescue
    url
  end

  def find_by_serial(serial, year: nil, require_all_keywords: nil, reject_keywords: nil)
    return [nil, 'АРШИН отключён'] unless enabled?

    s = serial.to_s.strip
    return [nil, 'Пустой серийный номер'] if s.empty?

    years =
      if year && !year.to_s.strip.empty?
        [year.to_s]
      else
        from_year = (ENV['ARSHIN_SERIAL_MIN_YEAR'] || '2019').to_i
        to_year = Time.now.year
        (from_year..to_year).to_a.reverse.map(&:to_s)
      end

    to_utf8 = lambda do |str|
      txt = str.to_s.dup.force_encoding('UTF-8')
      txt.valid_encoding? ? txt : txt.encode('UTF-8', invalid: :replace, undef: :replace)
    end
    require_dc = (require_all_keywords || []).map { |k| to_utf8.call(k).downcase }
    reject_dc = (reject_keywords || []).map { |k| to_utf8.call(k).downcase }

    candidates = []
    last_error = nil

    years.each_with_index do |y, idx|
      sleep(0.6) if idx > 0
      items, error = arshin_fetch_items_by_params({ 'mi_number' => s, 'year' => y, 'rows' => '100' }, return_full: true)
      if error
        last_error = error
        next
      end
      next if items.nil? || items.empty?

      items.each do |it|
        type_text = to_utf8.call(arshin_item_type_text(it)).downcase
        next if reject_dc.any? { |kw| !kw.empty? && type_text.include?(kw) }
        next unless require_dc.empty? || require_dc.all? { |kw| type_text.include?(kw) }

        date_str = it['verification_date'].to_s.strip
        d = begin
          Date.strptime(date_str, '%d.%m.%Y')
        rescue ArgumentError
          nil
        end

        it['_year'] = y
        candidates << { item: it, date: d }
      end
    end

    return [nil, last_error] if candidates.empty? && last_error
    return [nil, nil] if candidates.empty?

    candidates.sort_by! { |c| c[:date] ? -c[:date].to_time.to_i : 0 }
    [candidates.first[:item], nil]
  end

  def arshin_lookup_by_form(form)
    lookup_by_form_detailed(form)[:text]
  end

  VERIFICATION_INTERVAL_YEARS = 4

  def parse_meter_date_year(value)
    parse_meter_date(value)&.year
  end

  def parse_meter_date(value)
    raw = value.to_s.strip
    return nil if raw.empty?

    Date.strptime(raw, '%d.%m.%Y')
  rescue ArgumentError
    begin
      Date.iso8601(raw)
    rescue ArgumentError
      nil
    end
  end

  def suggest_search_years(valid_until, interval_years: VERIFICATION_INTERVAL_YEARS)
    current_year = Date.today.year
    default_years = ((current_year - 6)..current_year).to_a.reverse.map(&:to_s)
    fallback_years = (allowed_years + default_years).map(&:to_s).map(&:strip).reject(&:empty?)
    end_year = parse_meter_date_year(valid_until)

    return fallback_years.uniq if end_year.nil?

    preferred_years = []
    if end_year == current_year
      preferred_years << current_year
      preferred_years << (current_year - interval_years.to_i)
    else
      performed_year = end_year - interval_years.to_i
      preferred_years << performed_year
    end

    (preferred_years.map(&:to_s) + fallback_years).uniq
  end

  def lookup_for_meter(serial:, valid_until: nil, year: nil, org_title: nil, mit_notation: nil, meter_label: nil, preferred_mit_notation: nil, serial_key: nil, result_docnum: nil)
    lookup_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return { text: 'Интеграция АРШИН отключена (ARSHIN_ENABLED=0).', items: [], years_tried: [], suggested_years: [], used_preferred_type: false } unless enabled?

    number = utf8_text(serial).strip
    mit_notation = utf8_text(mit_notation).strip
    STDERR.puts "[ARSHIN LOOKUP] serial=#{number.inspect}, mit_notation=#{mit_notation.inspect}, serial_key=#{serial_key.inspect}"
    doc_number = result_docnum.to_s.strip
    if number.empty? && doc_number.empty?
      return { text: 'Укажите заводской номер прибора или номер свидетельства.', items: [], years_tried: [], suggested_years: [], used_preferred_type: false }
    end

    suggested_years =
      if year.to_s.strip.empty?
        interval = ArshinTypePriority.family_by_serial_key(serial_key) == 'pressure_sensor' ? 5 : VERIFICATION_INTERVAL_YEARS
        suggest_search_years(valid_until, interval_years: interval)
      else
        [year.to_s.strip]
      end

    org_for_search = org_title.to_s.strip
    auto_orgs = auto_org_titles
    org_chain = if org_for_search.empty?
      auto_orgs + ['']
    else
      [org_for_search]
    end

    profile_log('lookup_start', serial_key: serial_key, serial: number, mit: mit_notation, years: suggested_years.join(','), org_chain: org_chain.join(' | '))

    if number.empty? && !doc_number.empty?
      result = _search_by_doc_years(doc_number, suggested_years, org_chain, meter_label, year)
      profile_log('lookup_done', serial_key: serial_key, serial: number, items: Array(result[:items]).size, years_tried: Array(result[:years_tried]).join(','), ms: elapsed_ms(lookup_started_at))
      return result.merge(used_preferred_type: false)
    end

    # Пробуем сначала с preferred типом (серверная фильтрация аршина)
    preferred = utf8_text(preferred_mit_notation).strip
    use_preferred = !preferred.empty? && preferred != mit_notation.to_s.strip
    pool = ArshinTypePriority.pool_for(serial_key)
    pool = [preferred] + pool if use_preferred
    pool = pool.map(&:to_s).map(&:strip).reject(&:empty?).uniq

    # Сначала ищем строго по пулу приоритетных типов. Иначе общий поиск по номеру
    # может поймать чужой прибор в более свежем году и не дойти до правильного года.
    if use_preferred || !pool.empty?
      org_chain.each do |org_candidate|
        targeted = _meter_search_by_years(
          number,
          suggested_years,
          org_candidate,
          mit_notation,
          meter_label,
          year,
          max_rows: 100,
          preferred_filter_list: pool,
          preferred_rank_list: pool,
          target_valid_until: valid_until,
          serial_key: serial_key
        )
        return targeted.merge(used_preferred_type: true) unless Array(targeted[:items]).empty?
      end

      # Если по типам ничего не найдено, возвращаемся к широкому поиску по номеру,
      # но найденные типы все равно поднимаем выше в выдаче.
      org_chain.each do |org_candidate|
        result = _meter_search_by_years(number, suggested_years, org_candidate, mit_notation, meter_label, year, max_rows: 50, preferred_rank_list: pool, target_valid_until: valid_until, serial_key: serial_key)
        used = Array(result[:items]).any? { |it| pool.any? { |p| arshin_item_matches_type?(it, p) } }
        return result.merge(used_preferred_type: used) unless Array(result[:items]).empty?
      end
      return result.merge(used_preferred_type: false)
    end

    # Обычный поиск без preferred
    org_chain.each do |org_candidate|
      result = _meter_search_by_years(number, suggested_years, org_candidate, mit_notation, meter_label, year, target_valid_until: valid_until, serial_key: serial_key)
      return result.merge(used_preferred_type: false) unless Array(result[:items]).empty?
    end
    profile_log('lookup_done', serial_key: serial_key, serial: number, items: Array(result[:items]).size, years_tried: Array(result[:years_tried]).join(','), ms: elapsed_ms(lookup_started_at))
    result.merge(used_preferred_type: false)
  end

  def _search_by_doc_years(doc_number, suggested_years, org_titles_for_search, meter_label, year_hint)
    years_tried = []
    last_text = nil

    suggested_years.each_with_index do |y, idx|
      sleep(0.6) if idx.positive?
      years_tried << y
      Array(org_titles_for_search).each do |org_name|
        params = { 'search' => doc_number, 'year' => y, 'rows' => '100' }
        org = org_name.to_s.strip
        params['org_title'] = org unless org.empty?

        items, error = arshin_fetch_items_by_params(params, return_full: true, max_rows: 50)
        if error
          last_text = "❌ #{error}"
          next
        end

        filtered = Array(items).select do |item|
          item['result_docnum'].to_s.downcase.include?(doc_number.downcase)
        end
        next if filtered.empty?

        filtered = with_registry_links(filtered.map { |item| item.merge('_year' => y) })
        header = []
        header << "🔎 АРШИН — #{meter_label}" unless meter_label.to_s.strip.empty?
        header << "Свидетельство: #{doc_number}"
        header << "Год поиска: #{y}#{year_hint.to_s.strip.empty? ? ' (авто)' : ''}"
        header << "Поверитель: #{org}" unless org.empty?
        header << ''
        link = shorten_url(registry_link_for_serial(doc_number, year: y))
        return {
          text: (header + ["Найдено #{filtered.size} записей", "Проверить на АРШИН: #{link}"]).join("\n"),
          items: filtered.first(result_limit),
          year: y,
          years_tried: years_tried,
          suggested_years: suggested_years
        }
      end
    end

    years_line = years_tried.empty? ? '—' : years_tried.join(', ')
    {
      text: "🔎 По свидетельству №#{doc_number} ничего не найдено (годы: #{years_line}).\n#{last_text}",
      items: [],
      year: years_tried.last,
      years_tried: years_tried,
      suggested_years: suggested_years
    }
  end
  private_class_method :_search_by_doc_years

  def _meter_search_by_years(number, suggested_years, org_title, mit_notation, meter_label, year_hint, max_rows: nil, preferred_filter: nil, preferred_filter_list: nil, preferred_rank: nil, preferred_rank_list: nil, target_valid_until: nil, serial_key: nil)
    years_tried = []
    last_text = nil
    fallback_link = shorten_url(registry_link_for_serial(number, year: year_hint.to_s.strip.empty? ? nil : year_hint.to_s.strip))
    raw_number_for_query = utf8_text(number).strip
    number_candidates = [raw_number_for_query]
    compact_number_for_query = raw_number_for_query.dup.force_encoding('UTF-8').downcase.gsub(/\s+/, '')
    safe_mit_notation = utf8_text(mit_notation).strip
    temp_sensor_key = serial_key.to_s.start_with?('temp_sensor_serial_')
    is_ktptr = temp_sensor_key && safe_mit_notation.match?(/КТПТР|KTPTR/i)

    if is_ktptr && compact_number_for_query.match?(/\A\d+[аa]?\z/i)
      base = compact_number_for_query.sub(/[аa]\z/i, '')
      unless base.empty?
        number_candidates.unshift("#{base}/#{base}А")
        number_candidates << base unless base == compact_number_for_query
      end
      STDERR.puts "[ARSHIN KTPTR] is_ktptr=#{is_ktptr}, input=#{compact_number_for_query.inspect}, base=#{base.inspect}, candidates=#{number_candidates.inspect}"
    elsif !is_ktptr
      return_non_ktptr_log = temp_sensor_key
      STDERR.puts "[ARSHIN KTPTR] is_ktptr=#{is_ktptr}, mit_notation=#{safe_mit_notation.inspect}" if return_non_ktptr_log
      paired_base =
        if compact_number_for_query.match?(/\A\d+[гх]\z/)
          compact_number_for_query.sub(/[гх]\z/, '')
        elsif compact_number_for_query.match?(/\A\d+\z/)
          compact_number_for_query
        end
      unless paired_base.to_s.empty?
        number_candidates << paired_base
        number_candidates << "#{paired_base} г/х"
        number_candidates << "#{paired_base}г/х"
      end
    end
    if ArshinTypePriority.family_by_serial_key(serial_key) == 'pressure_sensor'
      if compact_number_for_query.match?(/\A\d+\z/)
        number_candidates.unshift("А#{compact_number_for_query}")
      elsif compact_number_for_query.match?(/\Aa\d+\z/i)
        number_candidates << compact_number_for_query.sub(/\Aa/i, '')
      end
    end
    number_candidates = number_candidates.map(&:strip).reject(&:empty?).uniq

    suggested_years.each_with_index do |y, idx|
      sleep(0.6) if idx.positive?
      year_items = []
      number_candidates.each do |candidate_number|
        form = { 'mi_number' => candidate_number, 'year' => y }
        org = org_title.to_s.strip
        form['org_title'] = org unless org.empty?
        notation = safe_mit_notation
        form['mit_notation'] = notation unless notation.empty?

        items, error = arshin_fetch_items_by_params(form, return_full: true, max_rows: max_rows)
        years_tried << y unless years_tried.include?(y)

        if error
          last_text = "❌ #{error}"
          next
        end

        last_text = "Найдено #{items.size} записей"

        # Клиентская фильтрация по preferred типу
        preferred_filters = Array(preferred_filter_list).map { |v| utf8_text(v).strip }.reject(&:empty?)
        preferred_filters << utf8_text(preferred_filter).strip if preferred_filters.empty? && preferred_filter && !preferred_filter.empty?
        unless preferred_filters.empty?
          items = items.select { |item| preferred_filters.any? { |type_name| arshin_item_matches_type?(item, type_name) } }
        end

        next if items.nil? || items.empty?
        items.each do |item|
          year_items << item.merge('_year' => y, '_query_number' => candidate_number)
        end
      end

      next if year_items.empty?

      # Дедуп и ранжирование:
      # 1) точное совпадение по запрошенному номеру (с учетом пробелов/дефисов),
      # 2) варианты с суффиксами (например, "г/х"),
      # 3) более свежая дата поверки.
      dedup = {}
      year_items.each do |item|
        key = [
          item['vri_id'].to_s.strip,
          item['id'].to_s.strip,
          item['mi_number'].to_s.strip.downcase,
          item['verification_date'].to_s.strip,
          item['org_title'].to_s.strip
        ].join('|')
        dedup[key] ||= item
      end
      merged = dedup.values

      raw_number = utf8_text(number).strip.downcase
      raw_number_compact = raw_number.gsub(/[^[:alnum:]]+/, '')
      target_valid_date = parse_meter_date(target_valid_until)
      preferred_rank_value = utf8_text(preferred_rank).strip
      preferred_rank_values = Array(preferred_rank_list).map { |v| utf8_text(v).strip }.reject(&:empty?).uniq
      merged.sort_by! do |item|
        mi = utf8_text(item['mi_number']).strip.downcase
        mi_compact = mi.gsub(/[^[:alnum:]]+/, '')
        preferred_type =
          if !preferred_rank_values.empty?
            idx = preferred_rank_values.find_index { |type_name| arshin_item_matches_type?(item, type_name) }
            idx.nil? ? 999 : idx
          elsif !preferred_rank_value.empty?
            arshin_item_matches_type?(item, preferred_rank_value) ? 0 : 1
          else
            0
          end
        exact = (mi == raw_number || mi_compact == raw_number_compact) ? 0 : 1
        suffix = (mi.start_with?(raw_number) && mi != raw_number) ? 0 : 1
        valid_match =
          if target_valid_date
            parse_meter_date(item['valid_date']) == target_valid_date ? 0 : 1
          else
            0
          end
        date_weight =
          begin
            -Date.strptime(item['verification_date'].to_s, '%d.%m.%Y').jd
          rescue StandardError
            0
          end
        [preferred_type, valid_match, suffix, exact, date_weight]
      end

      limit = (max_rows || result_limit).to_i
      merged = with_registry_links(merged.first(limit))
      link = shorten_url(registry_link_for_serial(number, year: y))
      header = []
      safe_meter_label = utf8_text(meter_label).strip
      safe_number = utf8_text(number).strip
      header << "🔎 АРШИН — #{safe_meter_label}" unless safe_meter_label.empty?
      header << "Номер: #{safe_number}"
      header << "Год поиска: #{y}#{year_hint.to_s.strip.empty? ? ' (авто)' : ''}"
      display_filters = Array(preferred_filter_list).map { |v| utf8_text(v).strip }.reject(&:empty?)
      display_filters << utf8_text(preferred_filter).strip if display_filters.empty? && preferred_filter && !preferred_filter.empty?
      unless display_filters.empty?
        header << "Тип: #{display_filters.first(4).join(', ')}#{display_filters.size > 4 ? '...' : ''}"
      end
      header << ''

      return {
        text: (header + ["Найдено #{merged.size} записей", "Проверить на АРШИН: #{link}"]).join("\n"),
        items: merged,
        year: y,
        years_tried: years_tried,
        suggested_years: suggested_years
      }
    end

    years_line = years_tried.empty? ? '—' : years_tried.join(', ')
    {
      text: "🔎 По №#{number} ничего не найдено (годы: #{years_line}).\n#{last_text}\nПроверить на АРШИН: #{fallback_link}",
      items: [],
      year: years_tried.last,
      years_tried: years_tried,
      suggested_years: suggested_years
    }
  end
  private_class_method :_meter_search_by_years

  def lookup_by_form_detailed(form)
    return { text: 'Интеграция АРШИН отключена (ARSHIN_ENABLED=0).', items: [] } unless enabled?

    params = arshin_form_normalize(form)
    user_compact = params.reject { |_k, v| v.nil? || v.to_s.strip.empty? }
    return { text: 'Заполните хотя бы одно поле перед поиском.', items: [] } if user_compact.empty?

    params['year'] = Time.now.year.to_s if params['year'].to_s.strip.empty?
    compact = params.reject { |_k, v| v.nil? || v.to_s.strip.empty? }
    log("lookup_by_form params=#{params.inspect} compact=#{compact.inspect}")

    items, error = arshin_fetch_items_by_params(compact)
    link_full = arshin_registry_link_by_params(compact)
    link = shorten_url(link_full)
    log("lookup_by_form result items_count=#{items.is_a?(Array) ? items.size : 'nil'} error=#{error.inspect} link=#{link}")

    return { text: "❌ Ошибка запроса к АРШИН: #{error}\nПроверить вручную: #{link}", items: [], year: params['year'] } if error
    return { text: "🔎 По запросу ничего не найдено.\nПроверить вручную: #{link}", items: [], year: params['year'] } if items.empty?

    lines = ["🔎 АРШИН: найдено #{items.size} записей", '']
    items = with_registry_links(items)
    items.each_with_index do |item, idx|
      lines << arshin_format_item(item, idx)
      lines << ''
    end
    lines << "Открыть в реестре: #{link}"
    { text: lines.join("\n"), items: items, year: params['year'] }
  end

  def max_inline_keyboard(button_rows)
    buttons = button_rows.map do |row|
      row.map do |button|
        {
          'type' => 'callback',
          'text' => button[:text].to_s,
          'payload' => button[:payload].to_s,
          'intent' => 'default'
        }
      end
    end

    [{
      'type' => 'inline_keyboard',
      'payload' => { 'buttons' => buttons }
    }]
  end

  def arshin_form_value(value)
    text = value.to_s.strip
    text.empty? ? 'не задано' : text
  end
  private_class_method :arshin_form_value

  def arshin_form_year_value(value)
    text = value.to_s.strip
    return "#{Time.now.year} (текущий, по умолчанию)" if text.empty?

    text
  end
  private_class_method :arshin_form_year_value

  def arshin_registry_link_by_params(params)
    p = params.transform_keys(&:to_s)
    cm_params = {}
    cm_params['filter_mi_number'] = p['mi_number'] if p['mi_number'] && !p['mi_number'].empty?
    cm_params['filter_org_title'] = p['org_title'] if p['org_title'] && !p['org_title'].empty?
    cm_params['activeYear'] = p['year'] if p['year'] && !p['year'].empty?
    cm_params['filter_mi_mitype'] = p['mit_notation'] if p['mit_notation'] && !p['mit_notation'].empty?

    return 'https://fgis.gost.ru/fundmetrology/cm/results' if cm_params.empty?

    "https://fgis.gost.ru/fundmetrology/cm/results?#{URI.encode_www_form(cm_params)}"
  end
  private_class_method :arshin_registry_link_by_params

  def arshin_http_client(uri)
    Net::HTTP.new(uri.host, uri.port)
  end
  private_class_method :arshin_http_client

  def arshin_execute_request(uri)
    http = arshin_http_client(uri)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds
    res = http.request(Net::HTTP::Get.new(uri))
    if res.code == '429'
      log("rate_limited sleeping=0.6s uri=#{uri}")
      sleep(0.6)
      http2 = arshin_http_client(uri)
      http2.use_ssl = (uri.scheme == 'https')
      http2.open_timeout = timeout_seconds
      http2.read_timeout = timeout_seconds
      res = http2.request(Net::HTTP::Get.new(uri))
    end
    res
  end
  private_class_method :arshin_execute_request

  def arshin_text_variants(text)
    raw = text.to_s.strip
    return [] if raw.empty?

    cyr_to_lat = {
      'А' => 'A', 'В' => 'B', 'Е' => 'E', 'К' => 'K', 'М' => 'M',
      'Н' => 'H', 'О' => 'O', 'Р' => 'P', 'С' => 'C', 'Т' => 'T', 'У' => 'Y', 'Х' => 'X',
      'а' => 'a', 'в' => 'b', 'е' => 'e', 'к' => 'k', 'м' => 'm',
      'н' => 'h', 'о' => 'o', 'р' => 'p', 'с' => 'c', 'т' => 't', 'у' => 'y', 'х' => 'x'
    }
    lat_to_cyr = cyr_to_lat.invert

    direct = raw.downcase
    to_lat = raw.chars.map { |ch| cyr_to_lat.fetch(ch, ch) }.join.downcase
    to_cyr = raw.chars.map { |ch| lat_to_cyr.fetch(ch, ch) }.join.downcase
    [direct, to_lat, to_cyr].uniq
  end
  private_class_method :arshin_text_variants

  def arshin_item_type_text(item)
    fields = %w[mit_notation mit_title]
    values = fields.map { |k| item[k] }.compact.map(&:to_s).reject(&:empty?)
    values << item.to_json if values.empty?
    values.join(' ')
  end
  private_class_method :arshin_item_type_text

  def arshin_item_matches_type?(item, type_filter)
    needle = type_filter.to_s.strip
    return true if needle.empty?

    haystack_variants = arshin_text_variants(arshin_item_type_text(item))
    needle_variants = arshin_text_variants(needle)
    return false if haystack_variants.empty? || needle_variants.empty?

    haystack_tokens = haystack_variants
      .flat_map { |text| text.split(/[^\p{L}\p{N}]+/) }
      .map(&:strip)
      .reject(&:empty?)
      .uniq

    needle_tokens = needle_variants
      .flat_map { |text| text.split(/[^\p{L}\p{N}]+/) }
      .map(&:strip)
      .reject(&:empty?)
      .uniq

    return false if haystack_tokens.empty? || needle_tokens.empty?

    needle_tokens.any? do |needle_token|
      haystack_tokens.any? { |token| token == needle_token || token.start_with?(needle_token) }
    end
  end
  private_class_method :arshin_item_matches_type?

  def arshin_mi_number_variants(mi_number)
    raw = mi_number.to_s.strip
    return [nil] if raw.empty?

    digits_only = raw.gsub(/[^0-9]/, '')
    variants = [raw]
    variants << digits_only unless digits_only.empty?
    compact = raw.downcase.gsub(/\s+/, '')
    if compact.match?(/\A\d+[гх]\z/)
      paired_base = compact.sub(/[гх]\z/, '')
      variants << paired_base
      variants << "#{paired_base} г/х"
      variants << "#{paired_base}г/х"
    elsif compact.match?(/\A\d+\z/)
      variants << "#{compact} г/х"
      variants << "#{compact}г/х"
    end
    variants << "#{digits_only[0, 2]}-#{digits_only[2..]}" if digits_only.length > 2
    variants.map { |v| v.to_s.strip }.reject(&:empty?).uniq
  end
  private_class_method :arshin_mi_number_variants

  def arshin_item_matches_number?(item, number_variants)
    variants = Array(number_variants).map { |v| v.to_s.strip.downcase }.reject(&:empty?).uniq
    return true if variants.empty?

    number_raw = item['mi_number'].to_s.strip.downcase
    return false if number_raw.empty?

    number_compact = number_raw.gsub(/[^[:alnum:]]+/, '')
    variants.any? do |needle|
      needle_compact = needle.gsub(/[^[:alnum:]]+/, '')
      next false if needle_compact.empty?

      number_raw.include?(needle) ||
        number_raw.start_with?(needle) ||
        number_compact.include?(needle_compact) ||
        number_compact.start_with?(needle_compact)
    end
  end
  private_class_method :arshin_item_matches_number?

  def arshin_fetch_items_by_params(params, return_full: false, max_rows: nil)
    fetch_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    req_total = 0
    req_ok = 0
    req_err = 0
    effective_limit = max_rows || result_limit
    query_base = { 'rows' => effective_limit }
    params.each do |k, v|
      value = v.to_s.strip
      next if value.empty?

      query_base[k.to_s] = value
    end

    type_filter = query_base['mit_notation'].to_s.strip
    type_variants = arshin_text_variants(type_filter)

    org_variants = [query_base['org_title']].compact
    if query_base['org_title'] && !query_base['org_title'].empty?
      org_raw = query_base['org_title'].strip
      if org_raw =~ /\A(ООО)\s+([^"«»]+)\z/i
        form = ::Regexp.last_match(1)
        name = ::Regexp.last_match(2).to_s.strip
        org_variants << "#{form} \"#{name}\""
        org_variants << "#{form} «#{name}»"
      end
      org_variants << org_raw.tr('«»', '""')
      org_variants << org_raw.gsub(/"([^"]*)"/, '«\1»')
    end
    org_variants = org_variants.map { |v| v.to_s.strip }.reject(&:empty?).uniq

    supported_type_keys = %w[mit_notation]
    keys = type_api_keys.select { |k| supported_type_keys.include?(k) }
    keys = ['mit_notation'] if keys.empty?
    keys.unshift('mit_notation') unless keys.include?('mit_notation')
    keys.uniq!

    number_variants = arshin_mi_number_variants(query_base['mi_number'])
    primary_number_variants = [number_variants.first]
    fallback_number_variants = number_variants.drop(1)

    build_param_variants = lambda do |number_values|
      variants = []
      (org_variants.empty? ? [nil] : org_variants).each do |org_title|
        number_values.each do |mi_number|
          qp_base = query_base.dup
          org_title ? qp_base['org_title'] = org_title : qp_base.delete('org_title')
          mi_number ? qp_base['mi_number'] = mi_number : qp_base.delete('mi_number')

          if type_filter.empty?
            variants << qp_base
            next
          end

          keys.each do |type_key|
            type_variants.each do |type_value|
              q = qp_base.dup
              q.delete('mit_notation') unless type_key == 'mit_notation'
              q[type_key] = type_value
              variants << q
            end
          end

          type_variants.each do |type_value|
            q = qp_base.dup
            q.delete('mit_notation')
            q['search'] = type_value
            variants << q
          end
        end
      end
      variants.uniq
    end

    primary_param_variants = build_param_variants.call(primary_number_variants)
    fallback_param_variants = fallback_number_variants.empty? ? [] : build_param_variants.call(fallback_number_variants)
    search_passes = [primary_param_variants]
    search_passes << fallback_param_variants unless fallback_param_variants.empty?

    fallback_scan_rows = 100
    last_error = nil
    had_success_response = false

    search_passes.each_with_index do |param_variants, pass_idx|
      log("search_pass=#{pass_idx + 1} param_variants=#{param_variants.size}")

      param_variants.each_with_index do |query_params, idx|
        uri = URI(api_base_url)
        uri.query = URI.encode_www_form(query_params)
        log("request[pass=#{pass_idx + 1} #{idx + 1}/#{param_variants.size}] #{uri}")

        res = arshin_execute_request(uri)
        req_total += 1
        body = res.body.to_s.force_encoding('UTF-8')
        log("response[pass=#{pass_idx + 1} #{idx + 1}] http=#{res.code} bytes=#{body.bytesize}")

        unless res.is_a?(Net::HTTPSuccess)
          req_err += 1
          api_message = begin
            parsed_error = JSON.parse(body)
            parsed_error['message'] || body[0, 300]
          rescue
            body[0, 300]
          end
          last_error = "АРШИН API HTTP #{res.code}: #{api_message}"
          next
        end

        parsed = JSON.parse(body)
        req_ok += 1
        items = parsed.dig('result', 'items')
        log("response[pass=#{pass_idx + 1} #{idx + 1}] items_count=#{items.is_a?(Array) ? items.size : 'not_array'}")
        return [[], nil] unless items.is_a?(Array)

        had_success_response = true
        next if items.empty?

        if type_filter.empty?
          return [return_full ? items : items.first(effective_limit), nil]
        end

        filtered = items.select { |item| arshin_item_matches_type?(item, type_filter) }
        log("response[pass=#{pass_idx + 1} #{idx + 1}] filtered_count=#{filtered.size} type=#{type_filter.inspect}")
        return [filtered.first(effective_limit), nil] unless filtered.empty?

        scan_uri = URI(api_base_url)
        scan_uri.query = URI.encode_www_form(query_params.merge('rows' => fallback_scan_rows))
        scan_res = arshin_execute_request(scan_uri)
        req_total += 1

        scan_body = scan_res.body.to_s.force_encoding('UTF-8')
        log("scan[pass=#{pass_idx + 1} #{idx + 1}] http=#{scan_res.code} rows=#{fallback_scan_rows} bytes=#{scan_body.bytesize}")
        unless scan_res.is_a?(Net::HTTPSuccess)
          req_err += 1
          next
        end
        req_ok += 1

        scan_parsed = JSON.parse(scan_body)
        scan_items = scan_parsed.dig('result', 'items')
        next unless scan_items.is_a?(Array) && !scan_items.empty?

        scan_filtered = scan_items.select { |item| arshin_item_matches_type?(item, type_filter) }
        log("scan[pass=#{pass_idx + 1} #{idx + 1}] items_count=#{scan_items.size} filtered_count=#{scan_filtered.size}")
        return [scan_filtered.first(effective_limit), nil] unless scan_filtered.empty?
      end
    end

    # Дополнительный мягкий проход:
    # если строгий поиск по mi_number ничего не дал, пробуем API-поиск по `search`,
    # затем фильтруем локально по вхождению номера прибора.
    unless query_base['mi_number'].to_s.strip.empty?
      number_needles = arshin_mi_number_variants(query_base['mi_number'])
      search_queries = number_needles.first(2)
      # Если пользователь задал поверителя, не делаем дополнительный проход "без поверителя":
      # это заметно ускоряет поиск и убирает лишний шум в выдаче.
      fallback_org_values = org_variants.empty? ? [nil] : org_variants
      search_queries.each_with_index do |needle, idx|
        fallback_org_values.each_with_index do |org_fallback, org_idx|
          search_params = query_base.dup
          search_params.delete('mi_number')
          search_params.delete('mit_notation')
          org_fallback ? search_params['org_title'] = org_fallback : search_params.delete('org_title')
          search_params['search'] = needle
          search_params['rows'] = fallback_scan_rows

          uri = URI(api_base_url)
          uri.query = URI.encode_www_form(search_params)
          log("fallback_number_search[#{idx + 1}/#{search_queries.size} org=#{org_idx + 1}/#{fallback_org_values.size}] #{uri}")

          res = arshin_execute_request(uri)
          req_total += 1
          body = res.body.to_s.force_encoding('UTF-8')
          unless res.is_a?(Net::HTTPSuccess)
            req_err += 1
            next
          end
          req_ok += 1

          parsed = JSON.parse(body) rescue {}
          items = parsed.dig('result', 'items')
          next unless items.is_a?(Array) && !items.empty?

          had_success_response = true
          by_number = items.select { |item| arshin_item_matches_number?(item, number_needles) }
          next if by_number.empty?

          by_type = type_filter.empty? ? by_number : by_number.select { |item| arshin_item_matches_type?(item, type_filter) }
          log("fallback_number_search[#{idx + 1}/#{org_idx + 1}] items=#{items.size} by_number=#{by_number.size} by_type=#{by_type.size}")

          selected = by_type.empty? ? by_number : by_type
          return [return_full ? selected.first(effective_limit) : selected.first(effective_limit), nil]
        end
      end
    end

    profile_log('fetch_done', req_total: req_total, req_ok: req_ok, req_err: req_err, ms: elapsed_ms(fetch_started_at), variants: primary_param_variants.size + fallback_param_variants.size, had_success: had_success_response, err: last_error.to_s[0, 120])
    log("fetch_by_params no_results had_success=#{had_success_response} last_error=#{last_error.inspect}")
    return [nil, last_error] if last_error && !had_success_response

    [[], nil]
  rescue => e
    log("fetch_by_params exception=#{e.class}: #{e.message}")
    [nil, "#{e.class}: #{e.message}"]
  end
  private_class_method :arshin_fetch_items_by_params

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
  private_class_method :elapsed_ms

  def profile_log(event, fields = {})
    kv = fields.map { |k, v| "#{k}=#{utf8_text(v)}" }.join(' ')
    STDERR.puts("[ARSHIN PROFILE] event=#{event} #{kv}")
  rescue StandardError
    nil
  end
  private_class_method :profile_log

  def arshin_format_item(item, idx)
    number = item['mi_number'].to_s.strip
    notation = item['mit_notation'].to_s.strip
    org = item['org_title'].to_s.strip
    verification_date = item['verification_date'].to_s.strip
    valid_date = item['valid_date'].to_s.strip
    doc = item['result_docnum'].to_s.strip
    applicability = item['applicability'] == true ? 'Да' : 'Нет'

    lines = []
    lines << "#{idx + 1}. № прибора: #{number.empty? ? '—' : number}"
    lines << "   Тип/обозн.: #{notation}" unless notation.empty?
    lines << "   Поверитель: #{org}" unless org.empty?
    lines << "   Дата поверки: #{verification_date}" unless verification_date.empty?
    lines << "   Действительна до: #{valid_date}" unless valid_date.empty?
    lines << "   Документ: #{doc}" unless doc.empty?
    lines << "   Пригодность: #{applicability}"
    lines.join("\n")
  end
  private_class_method :arshin_format_item
end
