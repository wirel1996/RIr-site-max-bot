# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'fileutils'

module YadiskService
  module_function

  API_BASE = 'https://cloud-api.yandex.net/v1/disk'
  TIMEOUT = 20
  CACHE_FILE = File.expand_path('../cache/yadisk_folders.json', __dir__)

  @folder_cache = { at: 0, items: [] }
  @cache_mutex = Mutex.new
  @disk_loaded = false
  @refresh_in_progress = false

  def token
    ENV['YANDEX_DISK_TOKEN'].to_s.strip
  end

  def base_path
    raw = (ENV['YANDEX_DISK_BASE_PATH'] || 'Фото узлов/Фото').to_s.dup.force_encoding('UTF-8')
    raw = raw.encode('UTF-8', invalid: :replace, undef: :replace) unless raw.valid_encoding?
    raw.strip.gsub(/\A\/+|\/+\z/, '')
  end

  def cache_ttl
    (ENV['YANDEX_DISK_CACHE_TTL'] || '600').to_i
  end

  def max_depth
    (ENV['YANDEX_DISK_MAX_DEPTH'] || '4').to_i
  end

  def enabled?
    !token.empty?
  end

  def request(method, path, params = {}, body = nil)
    uri = URI("#{API_BASE}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    req = case method
          when :get then Net::HTTP::Get.new(uri)
          when :put then Net::HTTP::Put.new(uri)
          when :post then Net::HTTP::Post.new(uri)
          when :delete then Net::HTTP::Delete.new(uri)
          end
    req['Authorization'] = "OAuth #{token}"
    req['Accept'] = 'application/json'
    req.body = body if body

    res = http.request(req)
    [res.code.to_i, res.body.to_s]
  end
  private_class_method :request

  def list_dir(path, limit: 200, offset: 0)
    code, body = request(:get, '/resources', {
      'path' => path,
      'limit' => limit,
      'offset' => offset,
      'fields' => '_embedded.items.name,_embedded.items.type,_embedded.total'
    })
    return [] unless code == 200

    parsed = JSON.parse(body) rescue {}
    items = parsed.dig('_embedded', 'items') || []
    items.select { |it| it['type'] == 'dir' }.map { |it| it['name'].to_s.dup.force_encoding('UTF-8') }
  end
  private_class_method :list_dir

  WORKERS = 8

  def list_dir_all(path)
    out = []
    offset = 0
    loop do
      names = list_dir(path, limit: 200, offset: offset)
      break if names.empty?

      out.concat(names)
      break if names.size < 200

      offset += 200
    end
    out
  end
  private_class_method :list_dir_all

  def walk_parallel(root, max_depth_val)
    queue = Queue.new
    queue << [root, 0]
    active = 0
    active_mutex = Mutex.new
    acc = []
    acc_mutex = Mutex.new

    workers = Array.new(WORKERS) do
      Thread.new do
        loop do
          item = nil
          active_mutex.synchronize do
            if !queue.empty?
              item = queue.pop(true) rescue nil
              active += 1 if item
            elsif active.zero?
              item = :done
            end
          end

          if item == :done
            queue << :done
            break
          end

          unless item
            sleep 0.05
            next
          end

          path, depth = item
          begin
            names = list_dir_all(path)
            names.each do |name|
              child = "#{path}/#{name}"
              acc_mutex.synchronize { acc << child }
              queue << [child, depth + 1] if depth + 1 <= max_depth_val
            end
          rescue
          ensure
            active_mutex.synchronize { active -= 1 }
          end
        end
      end
    end

    workers.each(&:join)
    acc
  end
  private_class_method :walk_parallel

  def load_disk_cache
    return nil unless File.exist?(CACHE_FILE)

    data = JSON.parse(File.read(CACHE_FILE, encoding: 'UTF-8'))
    return nil unless data.is_a?(Hash)
    return nil unless data['at'].is_a?(Integer)
    return nil unless data['items'].is_a?(Array)
    return nil unless data['base_path'] == base_path
    return nil unless data['depth'] == max_depth

    { at: data['at'], items: data['items'].map { |s| s.to_s.dup.force_encoding('UTF-8') } }
  rescue => e
    puts "yadisk disk cache load error: #{e.class}: #{e.message}"
    nil
  end
  private_class_method :load_disk_cache

  def save_disk_cache(cache)
    FileUtils.mkdir_p(File.dirname(CACHE_FILE))
    File.write(CACHE_FILE, JSON.generate({
      'at' => cache[:at],
      'base_path' => base_path,
      'depth' => max_depth,
      'items' => cache[:items]
    }), encoding: 'UTF-8')
  rescue => e
    puts "yadisk disk cache save error: #{e.class}: #{e.message}"
  end
  private_class_method :save_disk_cache

  def all_folders(force_refresh: false)
    now = Time.now.to_i

    cached_items, cache_at, have_data, need_bg_refresh = @cache_mutex.synchronize do
      if !@disk_loaded
        loaded = load_disk_cache
        @folder_cache = loaded if loaded
        @disk_loaded = true
      end

      cache_expired = (now - @folder_cache[:at]) > cache_ttl
      have = !@folder_cache[:items].empty?

      if force_refresh || !have
        # нет данных — придётся ждать синхронно
        [@folder_cache[:items], @folder_cache[:at], false, false]
      elsif cache_expired && !@refresh_in_progress
        @refresh_in_progress = true
        [@folder_cache[:items], @folder_cache[:at], true, true]
      else
        [@folder_cache[:items], @folder_cache[:at], true, false]
      end
    end

    if need_bg_refresh
      Thread.new do
        begin
          items = walk_parallel(base_path, max_depth)
          @cache_mutex.synchronize do
            @folder_cache = { at: Time.now.to_i, items: items }
            save_disk_cache(@folder_cache)
          end
        rescue => e
          puts "yadisk background refresh error: #{e.class}: #{e.message}"
        ensure
          @cache_mutex.synchronize { @refresh_in_progress = false }
        end
      end
    end

    return cached_items if have_data

    # первая загрузка или force_refresh — ждём синхронно
    items = walk_parallel(base_path, max_depth)
    @cache_mutex.synchronize do
      @folder_cache = { at: Time.now.to_i, items: items }
      save_disk_cache(@folder_cache)
    end
    items
  end

  def folder_display_name(full_path)
    s = full_path.to_s.dup.force_encoding('UTF-8')
    s.sub("#{base_path}/", '')
  end

  def compact_display_name(full_path)
    raw = folder_display_name(full_path)
    raw = raw.encode('UTF-8', invalid: :replace, undef: :replace) unless raw.valid_encoding?
    segments = raw.split('/').map(&:strip).reject(&:empty?)
    compacted = []
    segments.each do |seg|
      last = compacted.last
      if last && seg.downcase.start_with?(last.downcase)
        compacted[-1] = seg
      else
        compacted << seg
      end
    end
    compacted.join('/')
  end

  def subfolders(path)
    prefix = "#{path}/"
    all_folders.select do |p|
      next false unless p.start_with?(prefix)

      rest = p[prefix.length..]
      rest && !rest.empty? && !rest.include?('/')
    end.sort
  end

  def top_level_folders
    subfolders(base_path)
  end

  def has_subfolders?(path)
    prefix = "#{path}/"
    all_folders.any? { |p| p.start_with?(prefix) }
  end

  def search(query, limit: 500)
    q = query.to_s.dup.force_encoding('UTF-8')
    q = q.encode('UTF-8', invalid: :replace, undef: :replace) unless q.valid_encoding?
    q = q.downcase.strip
    return [] if q.empty?

    tokens = q.split(/\s+/).reject(&:empty?).map { |t| t.force_encoding('UTF-8') }
    return [] if tokens.empty?

    matches = all_folders.select do |path|
      display = folder_display_name(path).to_s.force_encoding('UTF-8').downcase
      tokens.all? { |t| display.include?(t) }
    end
    matches.first(limit)
  end

  def create_folder(name, parent: nil)
    cleaned = name.to_s.strip.gsub(/[\\\/:\*\?"<>|]/, '_')
    return [nil, 'Пустое имя папки'] if cleaned.empty?

    parent_path = parent.to_s.strip
    parent_path = base_path if parent_path.empty?
    full_path = "#{parent_path}/#{cleaned}"
    code, body = request(:put, '/resources', { 'path' => full_path })

    if code == 201
      @cache_mutex.synchronize do
        @folder_cache = { at: 0, items: [] }
        File.delete(CACHE_FILE) if File.exist?(CACHE_FILE)
      end
      [full_path, nil]
    elsif code == 409
      [full_path, nil]
    else
      msg = (JSON.parse(body)['message'] rescue body[0, 200])
      [nil, "Ошибка создания (HTTP #{code}): #{msg}"]
    end
  end

  def upload_from_url(folder_path, filename, source_url)
    dest = "#{folder_path}/#{filename}"
    code, body = request(:post, '/resources/upload', {
      'url' => source_url,
      'path' => dest,
      'disable_redirects' => 'false'
    })

    if code == 202
      [true, dest, nil]
    else
      msg = (JSON.parse(body)['message'] rescue body[0, 200])
      [false, dest, "HTTP #{code}: #{msg}"]
    end
  end

  def gspo_root_path
    raw = ENV.fetch('YANDEX_DISK_GSPO_PATH', 'Приборы учета/ГСПО').to_s.strip
    raw = "/#{raw}" unless raw.start_with?('/')
    raw.gsub(%r{/+\z}, '')
  end

  def sanitize_path_segment(text, max_len: 160)
    text.to_s.strip.gsub(/[\\\/:\*\?"<>|]/, '_').gsub(/\s+/, ' ').strip[0, max_len]
  end

  def gspo_object_folder(name:, address:)
    label = sanitize_path_segment(
      [name, address].map { |part| part.to_s.strip }.reject(&:empty?).join(' - ')
    )
    "#{gspo_root_path}/#{label}"
  end

  def ensure_path_exists(full_path)
    path = full_path.to_s.strip
    return [nil, 'Пустой путь'] if path.empty?

    parts = path.split('/').reject(&:empty?)
    built = ''
    parts.each do |part|
      built = built.empty? ? "/#{part}" : "#{built}/#{part}"
      code, body = request(:put, '/resources', { 'path' => built })
      next if [201, 409].include?(code)

      msg = (JSON.parse(body)['message'] rescue body.to_s[0, 200])
      return [nil, "Не удалось создать «#{built}» (HTTP #{code}): #{msg}"]
    end
    [built, nil]
  end

  def upload_gspo_arshin_pdf(name:, address:, local_path:, filename: nil)
    folder, err = ensure_path_exists(gspo_object_folder(name: name, address: address))
    return [false, nil, err] unless folder

    base = filename.to_s.strip
    base = File.basename(local_path.to_s) if base.empty?
    upload_file(folder, base, local_path, overwrite: true)
  end

  def upload_file(folder_path, filename, local_path, overwrite: true)
    return [false, nil, 'Токен Яндекс.Диска не задан'] unless enabled?
    return [false, nil, 'Файл не найден'] unless File.exist?(local_path.to_s)

    dest = "#{folder_path}/#{filename}"
    code, body = request(:get, '/resources/upload', {
      'path' => dest,
      'overwrite' => overwrite ? 'true' : 'false'
    })

    unless code == 200
      msg = (JSON.parse(body)['message'] rescue body[0, 200])
      return [false, dest, "HTTP #{code} (upload href): #{msg}"]
    end

    href = (JSON.parse(body)['href'] rescue nil)
    return [false, dest, 'Пустой href для загрузки'] if href.to_s.empty?

    uri = URI(href)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT * 3

    req = Net::HTTP::Put.new(uri.request_uri)
    req['Content-Type'] = 'application/octet-stream'
    req['Content-Length'] = File.size(local_path).to_s

    File.open(local_path, 'rb') do |f|
      req.body_stream = f
      res = http.request(req)
      put_code = res.code.to_i
      return [true, dest, nil] if [201, 202].include?(put_code)

      return [false, dest, "HTTP #{put_code}: #{res.body.to_s[0, 200]}"]
    end
  rescue => e
    [false, dest, "#{e.class}: #{e.message}"]
  end
end
