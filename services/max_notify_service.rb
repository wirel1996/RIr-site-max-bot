# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require_relative '../storage/app_settings'
require_relative '../storage/max_users_log'

module MaxNotifyService
  module_function

  MAX_API_URL = 'https://platform-api.max.ru/messages'

  def enabled?
    return false if ENV['CONTACTS_WEB_ENV'].to_s.strip == 'test'
    (ENV['MAX_ENABLED'] || '1').to_s.strip == '1' && !token.empty?
  end

  def notify_water_payment(text)
    return false unless enabled?

    chat_ids = water_payment_chat_ids
    return false if chat_ids.empty?

    Thread.new do
      chat_ids.each { |chat_id| send_to_chat(text, chat_id) }
    rescue StandardError => e
      warn "MAX notify error: #{e.class}: #{e.message}"
    end
    true
  end

  def notify_journal_event(text)
    return false unless enabled?

    chat_ids = journal_event_chat_ids
    return false if chat_ids.empty?

    Thread.new do
      chat_ids.each { |chat_id| send_to_chat(text, chat_id) }
    rescue StandardError => e
      warn "MAX notify error: #{e.class}: #{e.message}"
    end
    true
  end

  def notify_db_backup_event(text)
    return false unless enabled?

    chat_ids = db_backup_chat_ids
    return false if chat_ids.empty?

    Thread.new do
      chat_ids.each { |chat_id| send_to_chat(text, chat_id) }
    rescue StandardError => e
      warn "MAX notify error: #{e.class}: #{e.message}"
    end
    true
  end

  def deliver_to_chat(text, chat_id)
    return false unless enabled?

    cid = chat_id.to_i
    return false if cid <= 0

    send_to_chat(text, cid)
    true
  end

  def max_users
    MaxUsersLog.all.values
               .reject { |user| user['is_bot'] == true }
               .sort_by { |user| user['name'].to_s.empty? ? [user['last_name'].to_s, user['first_name'].to_s] : user['name'].to_s }
               .map do |user|
                 {
                   user_id: user['user_id'].to_s,
                   chat_id: user['chat_id'],
                   name: display_name(user),
                   first_seen: user['first_seen'],
                   has_chat: !user['chat_id'].to_s.empty?
                 }
               end
  end

  def water_payment_notify_user_id
    water_payment_notify_user_ids.first.to_s
  end

  def water_payment_notify_user_ids
    value = AppSettings.get('water_payment_notify_user_ids')
    ids = value.is_a?(Array) ? value : value.to_s.split(',')
    ids = [AppSettings.get('water_payment_notify_user_id')] if ids.empty?
    ids.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def set_water_payment_notify_user_id(user_id)
    set_water_payment_notify_user_ids([user_id]).first.to_s
  end

  def set_water_payment_notify_user_ids(user_ids)
    ids = Array(user_ids).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    users = MaxUsersLog.all
    ids.each do |user_id|
      user = users[user_id]
      raise ArgumentError, 'MAX пользователь не найден или у него нет chat_id' unless user && !user['chat_id'].to_s.empty?
    end

    AppSettings.set('water_payment_notify_user_ids', ids)
    AppSettings.set('water_payment_notify_user_id', ids.first.to_s)
    water_payment_notify_user_ids
  end

  def clear_chat_id(user_id)
    selected = water_payment_notify_user_ids
    set_water_payment_notify_user_ids(selected - [user_id.to_s]) if selected.include?(user_id.to_s)
    selected_journal = journal_notify_user_ids
    set_journal_notify_user_ids(selected_journal - [user_id.to_s]) if selected_journal.include?(user_id.to_s)
    MaxUsersLog.clear_chat_id(user_id)
  end

  def journal_notify_user_ids
    value = AppSettings.get('journal_notify_user_ids')
    ids = value.is_a?(Array) ? value : value.to_s.split(',')
    ids = [AppSettings.get('water_payment_notify_user_id')] if ids.empty?
    ids.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def journal_notify_logins
    value = AppSettings.get('journal_notify_logins')
    ids = value.is_a?(Array) ? value : value.to_s.split(',')
    ids.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def set_journal_notify_logins(logins)
    ids = Array(logins).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    AppSettings.set('journal_notify_logins', ids)
    journal_notify_logins
  end

  def site_user_max_bindings
    value = AppSettings.get('site_user_max_bindings')
    value.is_a?(Hash) ? value.transform_keys(&:to_s).transform_values { |v| v.to_s.strip } : {}
  end

  def set_site_user_max_bindings(bindings)
    raw = bindings.is_a?(Hash) ? bindings : {}
    users = MaxUsersLog.all
    normalized = {}
    raw.each do |login, max_user_id|
      key = login.to_s.strip
      next if key.empty?
      val = max_user_id.to_s.strip
      if !val.empty?
        user = users[val]
        raise ArgumentError, 'MAX пользователь не найден или у него нет chat_id' unless user && !user['chat_id'].to_s.empty?
      end
      normalized[key] = val
    end
    AppSettings.set('site_user_max_bindings', normalized)
    site_user_max_bindings
  end

  def set_journal_notify_user_ids(user_ids)
    ids = Array(user_ids).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    users = MaxUsersLog.all
    ids.each do |user_id|
      user = users[user_id]
      raise ArgumentError, 'MAX РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ РЅРµ РЅР°Р№РґРµРЅ РёР»Рё Сѓ РЅРµРіРѕ РЅРµС‚ chat_id' unless user && !user['chat_id'].to_s.empty?
    end

    AppSettings.set('journal_notify_user_ids', ids)
    journal_notify_user_ids
  end

  def db_backup_notify_user_id
    AppSettings.get('db_backup_notify_user_id').to_s.strip
  end

  def set_db_backup_notify_user_id(user_id)
    id = user_id.to_s.strip
    if id.empty?
      AppSettings.set('db_backup_notify_user_id', '')
      return ''
    end

    user = MaxUsersLog.all[id]
    raise ArgumentError, 'MAX пользователь не найден или у него нет chat_id' unless user && !user['chat_id'].to_s.empty?

    AppSettings.set('db_backup_notify_user_id', id)
    id
  end

  def display_name(user)
    name = user['name'].to_s.strip
    return name unless name.empty?

    [user['first_name'], user['last_name']].map(&:to_s).reject(&:empty?).join(' ')
  end
  private_class_method :display_name

  def water_payment_chat_ids
    users = MaxUsersLog.all
    water_payment_notify_user_ids.filter_map { |user_id| users.dig(user_id.to_s, 'chat_id') }
  end
  private_class_method :water_payment_chat_ids

  def journal_event_chat_ids
    users = MaxUsersLog.all
    logins = journal_notify_logins
    if logins.any?
      bindings = site_user_max_bindings
      return logins.filter_map { |login| users.dig(bindings[login].to_s, 'chat_id') }.uniq
    end

    journal_notify_user_ids.filter_map { |user_id| users.dig(user_id.to_s, 'chat_id') }.uniq
  end
  private_class_method :journal_event_chat_ids

  def db_backup_chat_ids
    id = db_backup_notify_user_id
    return [] if id.empty?
    chat_id = MaxUsersLog.all.dig(id, 'chat_id')
    chat_id.to_s.empty? ? [] : [chat_id]
  end
  private_class_method :db_backup_chat_ids

  def send_to_chat(text, chat_id)
    uri = URI("#{MAX_API_URL}?chat_id=#{chat_id}")
    payload = { text: text.to_s.gsub('*', '') }
    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => token
    }
    Net::HTTP.post(uri, payload.to_json, headers)
  end
  private_class_method :send_to_chat

  def token
    ENV['MAX_BOT_TOKEN'].to_s.strip
  end
  private_class_method :token
end
