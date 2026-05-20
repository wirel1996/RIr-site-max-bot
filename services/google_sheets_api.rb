# frozen_string_literal: true

# Тонкая обёртка над Google Sheets API v4 + OAuth refresh-token.
# Использует общие переменные GOOGLE_OAUTH_*. Безопасна для одновременного
# использования из разных сервисов с разными document_id.

require 'json'
require 'net/http'
require 'uri'

module GoogleSheetsAPI
  module_function

  API_BASE = 'https://sheets.googleapis.com/v4/spreadsheets'
  OAUTH_URL = 'https://oauth2.googleapis.com/token'
  TIMEOUT = (ENV['GOOGLE_HTTP_TIMEOUT'] || '30').to_i
  RETRIES = (ENV['GOOGLE_HTTP_RETRIES'] || '3').to_i

  @access_token = nil
  @access_token_expires_at = 0
  @token_mutex = Mutex.new

  def configured?
    !ENV['GOOGLE_OAUTH_CLIENT_ID'].to_s.strip.empty? &&
      !ENV['GOOGLE_OAUTH_CLIENT_SECRET'].to_s.strip.empty? &&
      !ENV['GOOGLE_OAUTH_REFRESH_TOKEN'].to_s.strip.empty?
  end

  def access_token
    @token_mutex.synchronize do
      if @access_token.nil? || Time.now.to_i >= @access_token_expires_at - 60
        refresh!
      end
      @access_token
    end
  end

  def refresh!
    uri = URI(OAUTH_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    req = Net::HTTP::Post.new(uri)
    req.set_form_data(
      'refresh_token' => ENV['GOOGLE_OAUTH_REFRESH_TOKEN'],
      'client_id'     => ENV['GOOGLE_OAUTH_CLIENT_ID'],
      'client_secret' => ENV['GOOGLE_OAUTH_CLIENT_SECRET'],
      'grant_type'    => 'refresh_token'
    )

    res = http.request(req)
    data = JSON.parse(res.body) rescue {}
    raise "OAuth refresh failed: HTTP #{res.code} #{res.body[0, 200]}" unless data['access_token']

    @access_token = data['access_token']
    @access_token_expires_at = Time.now.to_i + (data['expires_in'] || 3600).to_i
  end
  private_class_method :refresh!

  def request(method, document_id, path, params = {}, body = nil)
    attempts = [RETRIES, 1].max
    last_error = nil

    attempts.times do |idx|
      begin
        uri = URI("#{API_BASE}/#{document_id}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        req = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              when :put then Net::HTTP::Put.new(uri)
              else raise "unsupported method: #{method}"
              end
        req['Authorization'] = "Bearer #{access_token}"
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body) if body

        res = http.request(req)
        code = res.code.to_i
        response_body = res.body.to_s
        if retryable_http_code?(code) && idx < attempts - 1
          sleep(retry_delay(idx))
          next
        end
        return [code, response_body]
      rescue *retryable_exceptions => e
        last_error = e
        raise if idx >= attempts - 1

        sleep(retry_delay(idx))
      end
    end

    raise(last_error || 'Google request failed without response')
  end

  def retryable_exceptions
    [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError]
  end
  private_class_method :retryable_exceptions

  def retryable_http_code?(code)
    code == 429 || code >= 500
  end
  private_class_method :retryable_http_code?

  def retry_delay(attempt_idx)
    base = 0.5 * (2**attempt_idx)
    jitter = rand * 0.2
    base + jitter
  end
  private_class_method :retry_delay

  # Список всех вкладок (sheets) в документе.
  def list_sheets(document_id)
    code, body = request(:get, document_id, '', fields: 'sheets.properties(title,sheetId,index,gridProperties)')
    return [] unless code == 200

    (JSON.parse(body)['sheets'] || []).map do |s|
      props = s['properties'] || {}
      grid  = props['gridProperties'] || {}
      {
        id:    props['sheetId'].to_i,
        name:  props['title'].to_s,
        index: props['index'].to_i,
        rows:  grid['rowCount'].to_i,
        cols:  grid['columnCount'].to_i
      }
    end
  end

  # Прочитать диапазон. range — строка вида "A1:Z200" или "Sheet1!A1:Z200".
  # Если sheet передан, range считается относительным к нему.
  def read_range(document_id, sheet_or_range, range = nil)
    full_range = range ? "#{sheet_or_range}!#{range}" : sheet_or_range
    encoded = URI.encode_www_form_component(full_range)
    code, body = request(:get, document_id, "/values/#{encoded}", valueRenderOption: 'FORMATTED_VALUE')
    return [] unless code == 200

    JSON.parse(body)['values'] || []
  end

  # Батч-чтение нескольких диапазонов за один запрос (values:batchGet).
  # ranges — массив строк "Sheet!A1:Z200". Возвращает массив таблиц той же длины.
  def batch_get_ranges(document_id, ranges, batch_size: 50)
    return [] if ranges.empty?

    results = []
    ranges.each_slice(batch_size) do |chunk|
      query = chunk.map do |r|
        # В Windows-консоли/локали строка с кириллицей в имени листа может
        # оказаться не в UTF-8, а Google batchGet требует корректный UTF-8.
        range_utf8 = r.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
        ['ranges', range_utf8]
      end
      query << ['valueRenderOption', 'FORMATTED_VALUE']
      qs = URI.encode_www_form(query)
      code, body = request(:get, document_id, "/values:batchGet?#{qs}", {})
      if code != 200
        results.concat(Array.new(chunk.size, []))
        next
      end
      vr = (JSON.parse(body)['valueRanges'] || [])
      results.concat(vr.map { |r| r['values'] || [] })
    end
    results
  end

  # Записать одну ячейку.
  def write_cell(document_id, sheet, a1, value, value_input_option: 'USER_ENTERED')
    full_range = "#{sheet}!#{a1}"
    encoded = URI.encode_www_form_component(full_range)
    body = { range: full_range, values: [[value]] }
    code, resp = request(:put, document_id, "/values/#{encoded}", { valueInputOption: value_input_option }, body)
    if code == 200
      [true, nil]
    else
      msg = (JSON.parse(resp)['error']['message'] rescue resp[0, 200])
      [false, "HTTP #{code}: #{msg}"]
    end
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}"]
  end

  # Конвертация (row, col) — оба нуль-индексные — в A1-нотацию.
  # row=0, col=0 → "A1". row=4, col=27 → "AB5".
  def cell_a1(row, col)
    "#{column_letter(col)}#{row + 1}"
  end

  def column_letter(col)
    n = col + 1
    s = +''
    while n > 0
      n -= 1
      s.prepend(('A'.ord + (n % 26)).chr)
      n /= 26
    end
    s
  end
end
