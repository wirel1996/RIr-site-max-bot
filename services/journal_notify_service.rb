# frozen_string_literal: true

require 'json'
require 'date'
require 'fileutils'

require_relative '../storage/app_settings'
require_relative '../storage/journal_db'
require_relative '../storage/user_profiles'
require_relative '../storage/max_users_log'

# Доставка уведомлений об изменениях ячеек электронного журнала в MAX.
# Один обработчик за раз (mutex); повторная доставка блокируется в journal_notify_deliveries.
module JournalNotifyService
  module_function

  STATE_FILE = File.expand_path('../storage/journal_notify_state.json', __dir__)
  JOURNAL_NOTIFY_UTC_OFFSET = '+07:00'
  @state_mutex = Mutex.new
  @process_mutex = Mutex.new

  def normalize_person_name(value)
    s = value.to_s.downcase
    s = s.gsub(/[^\p{L}\p{N}\s\.]/u, ' ')
    s.gsub(/\s+/, ' ').strip
  end

  def person_match?(subscriber_name, journal_person)
    a = normalize_person_name(subscriber_name)
    b = normalize_person_name(journal_person)
    return false if a.empty? || b.empty?
    return true if a == b
    return true if b.start_with?("#{a} ") || b.start_with?(a)

    a.split.size == 1 && b.start_with?(a)
  end

  def bind_max_user(user_id, journal_or_sheets_name)
    key = user_id.to_s
    norm = normalize_person_name(journal_or_sheets_name)
    data = AppSettings.get('journal_subscriber_bindings')
    data = {} unless data.is_a?(Hash)
    if norm.empty?
      data.delete(key)
    else
      data[key] = norm
    end
    AppSettings.set('journal_subscriber_bindings', data)
    data
  end

  def unbind_max_user(user_id)
    bind_max_user(user_id, '')
  end

  def process_pending_events(deliver: nil)
    deliver ||= ->(_text, _chat_id) {}

    @process_mutex.synchronize do
      process_pending_events_locked(deliver)
    end
  rescue StandardError => e
    warn "JournalNotifyService.process_pending_events error: #{e.class}: #{e.message}"
    0
  end

  def process_pending_events_locked(deliver)
    last_id = load_last_id
    if last_id.nil?
      last_id = JournalDB.with_db { |db| JournalDB.latest_event_id(db).to_i }
      save_last_id(last_id)
      return 0
    end

    today = Time.now.getlocal(JOURNAL_NOTIFY_UTC_OFFSET).to_date
    tomorrow = today + 1
    sent = 0

    JournalDB.with_db do |db|
      events = JournalDB.events_since(db, last_id, limit: 100)
      if events.size > 15
        oldest_ts = events.first['created_at'].to_i
        if oldest_ts < Time.now.to_i - 120
          tail = events.last['id'].to_i
          save_last_id(tail)
          warn "JournalNotifyService: пропущена старая очередь (#{events.size} событий), last_id=#{tail}"
          return 0
        end
      end

      events.each do |ev|
        ev_id = ev['id'].to_i
        ev_date = Date.iso8601(ev['date_iso'].to_s) rescue nil
        in_range = ev_date && (ev_date == today || ev_date == tomorrow)

        if in_range
          recipients_for_event(ev['person'].to_s).each do |chat_id|
            next if JournalDB.notify_delivered?(db, ev_id, chat_id)

            deliver.call(format_event(ev), chat_id)
            JournalDB.mark_notify_delivered(db, ev_id, chat_id)
            sent += 1
          rescue StandardError => e
            warn "JournalNotifyService send error event=#{ev_id} chat=#{chat_id}: #{e.class}: #{e.message}"
          end
        end

        save_last_id(ev_id)
      end
    end

    sent
  end
  private_class_method :process_pending_events_locked

  def format_event(ev)
    edited_at = Time.at(ev['created_at'].to_i).getlocal('+07:00').strftime('%d.%m.%Y %H:%M:%S')
    old_v = ev['old_value'].to_s.strip
    new_v = ev['new_value'].to_s.strip
    old_v = 'пусто' if old_v.empty?
    new_v = 'пусто' if new_v.empty?
    [
      '🔔 Изменение в электронном журнале',
      "Слот: #{ev['date_iso']} #{ev['time_slot']} — #{ev['person']}",
      "Было: #{old_v}",
      "Стало: #{new_v}",
      "Изменено: #{edited_at}"
    ].join("\n")
  end

  def recipients_for_event(journal_person)
    seen = {}
    add = lambda do |chat_id|
      cid = chat_id.to_i
      seen[cid] = true if cid.positive?
    end

    bindings = journal_subscriber_bindings
    UserProfiles.each_user do |uid, profile|
      chat_id = profile['chat_id'].to_i
      next if chat_id <= 0

      bound = bindings[uid.to_s].to_s.strip
      label = bound.empty? ? profile['name'].to_s : bound
      next if label.strip.empty?
      next unless person_match?(label, journal_person)

      add.call(chat_id)
    end

    site_login_recipients(journal_person).each { |cid| add.call(cid) }

    seen.keys
  end

  def site_login_recipients(journal_person)
    logins = journal_notify_logins
    return [] if logins.empty?

    bindings = site_user_max_bindings
    users = MaxUsersLog.all
    out = []
    logins.each do |login|
      next unless person_match?(login, journal_person)

      max_id = bindings[login.to_s].to_s
      next if max_id.empty?

      cid = users.dig(max_id, 'chat_id').to_i
      out << cid if cid.positive?
    end
    out.uniq
  end

  def journal_subscriber_bindings
    v = AppSettings.get('journal_subscriber_bindings')
    v.is_a?(Hash) ? v : {}
  rescue StandardError
    {}
  end

  def journal_notify_logins
    value = AppSettings.get('journal_notify_logins')
    ids = value.is_a?(Array) ? value : value.to_s.split(',')
    ids.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def site_user_max_bindings
    value = AppSettings.get('site_user_max_bindings')
    value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
  end

  def load_last_id
    @state_mutex.synchronize do
      return nil unless File.exist?(STATE_FILE)

      raw = JSON.parse(File.read(STATE_FILE, encoding: 'UTF-8'))
      v = raw['last_event_id']
      v.nil? ? nil : v.to_i
    end
  rescue StandardError
    nil
  end

  def save_last_id(id)
    @state_mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(STATE_FILE))
      File.write(STATE_FILE, JSON.generate(last_event_id: id.to_i), encoding: 'UTF-8')
    end
  rescue StandardError => e
    warn "JournalNotifyService.save_last_id error: #{e.class}: #{e.message}"
  end
end
