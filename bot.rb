#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['TZ'] = 'Asia/Novosibirsk' if Gem.win_platform?

require 'dotenv/load'
require 'json'
require 'net/http'
require 'uri'
require 'socket'
require 'fileutils'
require 'time'
require 'rufus-scheduler'
require_relative 'services/arshin_service'
require_relative 'services/algorithms_service'
require_relative 'services/devices_info_service'
require_relative 'services/yadisk_service'
require_relative 'services/sheets_service'
require_relative 'services/volume_calc_service'
require_relative 'services/billing_service'
require_relative 'services/verification_pdf_service'
require_relative 'services/contacts_service'
require_relative 'services/contacts_sync_service'
require_relative 'services/max_notify_service'
require_relative 'services/journal_service'
require_relative 'services/journal_notify_service'
require_relative 'services/db_backup_service'
require_relative 'services/water_registry_service'
require_relative 'storage/user_profiles'
require_relative 'storage/max_users_log'
require_relative 'storage/journal_db'
require_relative 'storage/app_settings'

%w[http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY].each do |key|
  ENV.delete(key)
end

MAX_ENABLED = (ENV['MAX_ENABLED'] || '1').to_s.strip == '1'
MAX_BOT_TOKEN = ENV['MAX_BOT_TOKEN'].to_s.strip

MAX_API_URL = 'https://platform-api.max.ru/messages'
MAX_INBOUND_ENABLED = (ENV['MAX_INBOUND_ENABLED'] || '1').to_s.strip == '1'
MAX_POLL_INTERVAL = (ENV['MAX_POLL_INTERVAL'] || '3').to_i
MAX_WEBHOOK_ENABLED = (ENV['MAX_WEBHOOK_ENABLED'] || '0').to_s.strip == '1'
MAX_WEBHOOK_PORT = (ENV['MAX_WEBHOOK_PORT'] || '8080').to_i
MAX_WEBHOOK_PATH = (ENV['MAX_WEBHOOK_PATH'] || '/max/webhook').to_s
MAX_PROCESSED_TTL_SECONDS = (ENV['MAX_PROCESSED_TTL_SECONDS'] || '600').to_i
MAX_DEBUG = (ENV['MAX_DEBUG'] || '0').to_s.strip == '1'
MAX_LOG_PATH = File.expand_path((ENV['MAX_LOG_PATH'] || './log/max.log').to_s, __dir__)
MAX_LOG_IDENTITY = (ENV['MAX_LOG_IDENTITY'] || '1').to_s.strip == '1'

MAX_USER_STATES = {}
MAX_PROCESSED_KEYS = {}
MAX_STATES_MUTEX = Mutex.new
MAX_PROCESSED_MUTEX = Mutex.new

PENDING_SNAPSHOTS = {}
PENDING_SNAPSHOTS_MUTEX = Mutex.new
PENDING_SNAPSHOTS_TTL = (ENV['PENDING_SNAPSHOTS_TTL'] || '3600').to_i

def pending_snapshot_set(chat_id, info)
  PENDING_SNAPSHOTS_MUTEX.synchronize do
    old = PENDING_SNAPSHOTS[chat_id]
    VerificationPdfService.cleanup_file(old[:path]) if old && old[:path]
    PENDING_SNAPSHOTS[chat_id] = info.merge(at: Time.now.to_i)
  end
end

def pending_snapshot_get(chat_id)
  PENDING_SNAPSHOTS_MUTEX.synchronize do
    info = PENDING_SNAPSHOTS[chat_id]
    return nil unless info

    if (Time.now.to_i - info[:at].to_i) > PENDING_SNAPSHOTS_TTL
      VerificationPdfService.cleanup_file(info[:path])
      PENDING_SNAPSHOTS.delete(chat_id)
      return nil
    end
    return nil unless info[:path] && File.exist?(info[:path])

    info
  end
end

def pending_snapshot_clear(chat_id, delete_file: true)
  PENDING_SNAPSHOTS_MUTEX.synchronize do
    info = PENDING_SNAPSHOTS.delete(chat_id)
    VerificationPdfService.cleanup_file(info[:path]) if delete_file && info && info[:path]
    info
  end
end

def pending_snapshot?(chat_id)
  !pending_snapshot_get(chat_id).nil?
end

def max_log(message)
  FileUtils.mkdir_p(File.dirname(MAX_LOG_PATH))
  File.open(MAX_LOG_PATH, 'a', encoding: 'utf-8') do |f|
    f.puts "[#{Time.now.iso8601}] #{message}"
  end
rescue => e
  puts "max_log error: #{e.class}: #{e.message}"
end

def plain_text_for_max(text)
  text.to_s.gsub('*', '')
end

def send_to_max_chat(text, to_chat_id, attachments: nil)
  return unless MAX_ENABLED
  return if MAX_BOT_TOKEN.empty? || to_chat_id.to_s.empty?

  uri = URI("#{MAX_API_URL}?chat_id=#{to_chat_id}")
  payload = { text: plain_text_for_max(text) }
  payload[:attachments] = attachments if attachments && !attachments.empty?
  headers = {
    'Content-Type' => 'application/json',
    'Authorization' => MAX_BOT_TOKEN
  }
  Net::HTTP.post(uri, payload.to_json, headers)
rescue => e
  puts "MAX send error: #{e.class}: #{e.message}"
end

def max_answer_callback(callback_id, notification: nil)
  return if callback_id.to_s.empty?

  uri = URI("https://platform-api.max.ru/answers?callback_id=#{URI.encode_www_form_component(callback_id)}")
  headers = {
    'Content-Type' => 'application/json',
    'Authorization' => MAX_BOT_TOKEN
  }
  body = {}
  body['notification'] = notification if notification
  Net::HTTP.post(uri, body.to_json, headers)
rescue => e
  puts "MAX answers error: #{e.class}: #{e.message}"
end

def max_main_menu_keyboard
  rows = [
    [{ text: 'Поверка приборов в АРШИН', payload: 'Поверка приборов в АРШИН' }],
    [{ text: 'Расчёты', payload: 'Расчёты' }],
    [{ text: 'Алгоритмы и информация', payload: 'Алгоритмы' }]
  ]
  rows << [{ text: 'Электронные журналы', payload: 'Электронные журналы' }] if SheetsService.enabled? || BillingService.enabled?
  rows << [{ text: 'Загрузка фото на Я.Диск', payload: 'Загрузка фото' }] if YadiskService.enabled?
  ArshinService.max_inline_keyboard(rows)
end

def max_yadisk_search_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

YADISK_ROOT_PAGE_SIZE = 10

def max_yadisk_root_keyboard(folders, page: 0)
  total = folders.size
  page_count = [(total + YADISK_ROOT_PAGE_SIZE - 1) / YADISK_ROOT_PAGE_SIZE, 1].max
  page = 0 if page < 0
  page = page_count - 1 if page >= page_count
  start_idx = page * YADISK_ROOT_PAGE_SIZE
  slice = folders[start_idx, YADISK_ROOT_PAGE_SIZE] || []

  rows = slice.each_with_index.map do |path, i|
    global_idx = start_idx + i
    label = path.to_s.split('/').last
    [{ text: "📁 #{label}", payload: "ydisk:root:#{global_idx}" }]
  end

  if page_count > 1
    nav = []
    nav << { text: '← Пред.', payload: 'ydisk:root_page:prev' } if page > 0
    nav << { text: "#{page + 1}/#{page_count}", payload: 'ydisk:root_page:noop' }
    nav << { text: 'След. →', payload: 'ydisk:root_page:next' } if page < page_count - 1
    rows << nav
  end

  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

YADISK_PAGE_SIZE = 8

def max_yadisk_folders_keyboard(folders, page: 0)
  total = folders.size
  page_count = ((total + YADISK_PAGE_SIZE - 1) / YADISK_PAGE_SIZE)
  page_count = 1 if page_count < 1
  page = 0 if page < 0
  page = page_count - 1 if page >= page_count

  start_idx = page * YADISK_PAGE_SIZE
  slice = folders[start_idx, YADISK_PAGE_SIZE] || []

  rows = slice.each_with_index.map do |path, i|
    global_idx = start_idx + i
    [{ text: YadiskService.compact_display_name(path), payload: "ydisk:pick:#{global_idx}" }]
  end

  if page_count > 1
    nav = []
    nav << { text: '← Пред.', payload: 'ydisk:page:prev' } if page > 0
    nav << { text: "#{page + 1}/#{page_count}", payload: 'ydisk:page:noop' }
    nav << { text: 'След. →', payload: 'ydisk:page:next' } if page < page_count - 1
    rows << nav
  end

  rows << [{ text: 'Искать снова', payload: 'ydisk:retry' }, { text: 'Создать папку', payload: 'ydisk:create' }]
  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_yadisk_notfound_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: 'Искать снова', payload: 'ydisk:retry' }],
    [{ text: 'Создать папку', payload: 'ydisk:create' }],
    [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def max_yadisk_upload_keyboard(next_task_info = nil, has_pending_snapshot: false)
  rows = []
  rows << [{ text: '📥 Положить PDF сюда', payload: 'ydisk:putsnap' }] if has_pending_snapshot
  rows << [{ text: "➡ Следующее задание (#{next_task_info[:time]})", payload: 'ydisk:next_task' }] if next_task_info
  rows << [{ text: '➕ Создать подпапку', payload: 'ydisk:create_sub_here' }]
  rows << [{ text: 'Сменить папку', payload: 'ydisk:retry' }]
  rows << [{ text: 'Завершить', payload: 'Назад' }]
  ArshinService.max_inline_keyboard(rows)
end

def sheets_next_task_with_address(ctx)
  return nil unless ctx.is_a?(Hash) && ctx[:name] && ctx[:date]

  date = Date.iso8601(ctx[:date].to_s) rescue nil
  return nil unless date

  tasks = SheetsService.tasks_for(ctx[:name].to_s, date)
  start = ctx[:task_index].to_i + 1
  (start...tasks.size).each do |i|
    t = tasks[i]
    next unless SheetsService.extract_address_from_task(t[:task])

    return { index: i, time: t[:time] }
  end
  nil
end

def max_journals_menu_keyboard(user_id)
  rows = []
  rows << [{ text: 'Электронный журнал', payload: 'Электронный журнал' }] if SheetsService.enabled?
  rows << [{ text: 'ГВС биллинг', payload: 'ГВС биллинг' }] if BillingService.enabled? && BillingService.user_allowed?(user_id)
  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

BILLING_RESULTS_PAGE_SIZE = 8

def max_billing_menu_keyboard(_user_id = nil)
  ArshinService.max_inline_keyboard([
    [{ text: '🔍 Поиск по абоненту / адресу', payload: 'billing:search' }],
    [{ text: '📅 Создать следующий месяц', payload: 'billing:new_month_ask' }],
    [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def billing_menu_greeting
  current = BillingService.current_sheet
  tab = current ? current[:name] : nil
  tab ? "ГВС биллинг — открыт месяц «#{tab}»\nЧто делаем?" : 'ГВС биллинг — что делаем?'
rescue => e
  max_log("billing_menu_greeting error: #{e.class}: #{e.message}")
  'ГВС биллинг — что делаем?'
end

def max_billing_confirm_new_month_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: '✅ Да, создать', payload: 'billing:new_month_confirm' }],
    [{ text: 'Отмена', payload: 'billing:menu' }],
    [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def max_billing_search_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: 'Отмена', payload: 'billing:menu' }],
    [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def max_billing_results_keyboard(matches, page: 0)
  total = matches.size
  page_count = [(total + BILLING_RESULTS_PAGE_SIZE - 1) / BILLING_RESULTS_PAGE_SIZE, 1].max
  page = 0 if page < 0
  page = page_count - 1 if page >= page_count
  start_idx = page * BILLING_RESULTS_PAGE_SIZE
  slice = matches[start_idx, BILLING_RESULTS_PAGE_SIZE] || []

  rows = slice.each_with_index.map do |m, i|
    global_idx = start_idx + i
    label = "#{m[:name]} — #{m[:address]}"
    [{ text: label[0, 60], payload: "billing:pick:#{global_idx}" }]
  end

  if page_count > 1
    nav = []
    nav << { text: '← Пред.', payload: 'billing:page:prev' } if page > 0
    nav << { text: "#{page + 1}/#{page_count}", payload: 'billing:page:noop' }
    nav << { text: 'След. →', payload: 'billing:page:next' } if page < page_count - 1
    rows << nav
  end

  rows << [{ text: 'Новый поиск', payload: 'billing:search' }, { text: 'В меню', payload: 'billing:menu' }]
  rows << [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_billing_card_keyboard(has_serial: true, has_arshin_snap: false)
  rows = []
  rows << [{ text: '✏ Ввести показания', payload: 'billing:enter_value' }]
  rows << [{ text: '🔍 Проверить в АРШИН', payload: 'billing:check_arshin' }] if has_serial
  rows << [{ text: '📄 Положить PDF в папку на Я.Диск', payload: 'billing:put_arshin_snap' }] if has_arshin_snap
  rows << [{ text: 'К результатам', payload: 'billing:back_results' }, { text: 'В меню', payload: 'billing:menu' }]
  rows << [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_billing_cancel_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: 'Отмена', payload: 'billing:back_card' }],
    [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def max_billing_date_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: 'Сегодня', payload: 'billing:date:today' }],
    [{ text: 'Отмена', payload: 'billing:back_card' }],
    [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def billing_format_card(details)
  lines = [
    "📋 #{details[:name]}",
    "📍 #{details[:address]}",
    '',
    "Дата ввода в эксплуатацию: #{details[:commissioned].empty? ? '—' : details[:commissioned]}",
    "Дата следующей поверки: #{details[:poverka_next].empty? ? '—' : details[:poverka_next]}",
    "Заводской номер: #{details[:serial].empty? ? '—' : details[:serial]}",
    '',
    "Дата передачи конечных: #{details[:final_date].empty? ? '—' : details[:final_date]}",
    "Конечные показания: #{details[:final_value].empty? ? '—' : details[:final_value]}"
  ]
  unless details[:current_value].empty? && details[:current_date].empty?
    lines << ''
    lines << "Уже введены текущие:"
    lines << "  дата: #{details[:current_date].empty? ? '—' : details[:current_date]}"
    lines << "  показания: #{details[:current_value].empty? ? '—' : details[:current_value]}"
  end
  lines.join("\n")
end

def max_sheets_people_keyboard(people, subscribed_name = nil)
  rows = []
  if subscribed_name && people.include?(subscribed_name)
    idx = people.index(subscribed_name)
    rows << [{ text: "⭐ Моё расписание (#{subscribed_name})", payload: "sheets:who:#{idx}" }]
  end
  people.each_with_index do |name, idx|
    rows << [{ text: name, payload: "sheets:who:#{idx}" }]
  end
  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_devices_node_keyboard(path)
  node = DevicesInfoService.node_by_path(path)
  rows = []
  if node && node[:children]
    node[:children].each_with_index do |child, idx|
      rows << [{ text: child[:title], payload: "devices:go:#{idx}" }]
    end
  end
  if path.empty?
    rows << [{ text: '📑 К списку алгоритмов', payload: 'algo:menu' }]
  else
    rows << [{ text: '← Назад', payload: 'devices:up' }, { text: '📑 К алгоритмам', payload: 'algo:menu' }]
  end
  rows << [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

CONTACTS_ADMIN_USER_IDS = (ENV['BILLING_MONTH_CREATOR_IDS'] || ENV['BILLING_ALLOWED_USER_IDS']).to_s
                            .split(',').map(&:strip).reject(&:empty?)
MAX_CONTACTS_PAGE_SIZE = 20
MAX_CONTACTS_SEARCH_LIMIT = 25

def contacts_admin?(user_id)
  CONTACTS_ADMIN_USER_IDS.include?(user_id.to_s)
end

def max_contacts_menu_keyboard(user_id = nil)
  counts = ContactsService.counts
  rows = ContactsService.categories.map do |cat|
    label = ContactsService.category_label(cat)
    count = counts[cat].to_i
    [{ text: "#{label} (#{count})", payload: "contacts:cat:#{cat}" }]
  end
  rows << [{ text: '🔍 Поиск по всем', payload: 'contacts:search' }]
  rows << [{ text: '🔄 Обновить из Google Sheets', payload: 'contacts:sync' }] if contacts_admin?(user_id)
  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_contacts_list_keyboard(category, page, total)
  page_count = [(total + MAX_CONTACTS_PAGE_SIZE - 1) / MAX_CONTACTS_PAGE_SIZE, 1].max
  rows = []
  if page_count > 1
    nav = []
    nav << { text: '← Пред.', payload: 'contacts:list_page:prev' } if page > 0
    nav << { text: "#{page + 1}/#{page_count}", payload: 'contacts:list_page:noop' }
    nav << { text: 'След. →', payload: 'contacts:list_page:next' } if page < page_count - 1
    rows << nav
  end
  rows << [{ text: '⬅ К категориям', payload: 'contacts:menu' }]
  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_contacts_search_input_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: '⬅ К категориям', payload: 'contacts:menu' }],
    [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def max_contacts_detail_keyboard(record, return_payload)
  rows = []
  rows << [{ text: '⬅ Назад к списку', payload: return_payload }]
  rows << [{ text: '⬅ К категориям', payload: 'contacts:menu' }]
  rows << [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def contacts_open_menu(chat_id, user_id: nil)
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'contacts_menu' } }
  last = ContactsService.last_sync_at
  hint = last ? "\nПоследняя синхронизация: #{Time.at(last).strftime('%d.%m.%Y %H:%M')}" : "\nПока не синхронизировано — нажмите «Обновить»."
  send_to_max_chat(
    "📞 Контакты потребителей. Выберите категорию:#{hint}",
    chat_id,
    attachments: max_contacts_menu_keyboard(user_id)
  )
end

def contacts_show_list_page(chat_id, category, page)
  rows, total = ContactsService.list(category, page: page, page_size: MAX_CONTACTS_PAGE_SIZE)
  if total.zero?
    send_to_max_chat(
      "В категории «#{ContactsService.category_label(category)}» нет записей. Попробуйте обновить из Google Sheets.",
      chat_id,
      attachments: max_contacts_menu_keyboard(nil)
    )
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'contacts_menu' } }
    return
  end

  state = { mode: 'contacts_list', category: category, page: page, total: total, ids: rows.map { |r| r['id'].to_i } }
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state }

  start_idx = page * MAX_CONTACTS_PAGE_SIZE
  body_lines = ["📞 #{ContactsService.category_label(category)} — всего #{total}", '']
  rows.each_with_index do |row, i|
    body_lines << "#{start_idx + i + 1}. #{ContactsService.short_label(row)}"
  end
  body_lines << ''
  body_lines << 'Введите номер записи (#) для просмотра, либо листайте страницы.'

  send_to_max_chat(body_lines.join("\n"), chat_id, attachments: max_contacts_list_keyboard(category, page, total))
end

def contacts_show_detail_from_list(chat_id, list_index)
  state = MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] }
  return false unless state && state[:mode] == 'contacts_list'

  ids = state[:ids] || []
  page = state[:page].to_i
  page_offset = page * MAX_CONTACTS_PAGE_SIZE
  local_idx = list_index - page_offset
  return false unless local_idx >= 0 && local_idx < ids.size

  record = ContactsService.find(ids[local_idx])
  return false unless record

  return_payload = "contacts:cat:#{state[:category]}:page:#{page}"
  send_to_max_chat(
    ContactsService.detail_text(record),
    chat_id,
    attachments: max_contacts_detail_keyboard(record, return_payload)
  )
  true
end

def contacts_show_search_results(chat_id, query)
  results = ContactsService.search(query).first(MAX_CONTACTS_SEARCH_LIMIT)
  if results.empty?
    send_to_max_chat(
      "По запросу «#{query}» ничего не найдено.",
      chat_id,
      attachments: max_contacts_search_input_keyboard
    )
    return
  end

  state = { mode: 'contacts_search_results', query: query, ids: results.map { |r| r['id'].to_i } }
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state }

  body_lines = ["🔍 По запросу «#{query}» найдено #{results.size}", '']
  results.each_with_index do |row, i|
    body_lines << "#{i + 1}. [#{ContactsService.category_label(row['category'])}] #{ContactsService.short_label(row)}"
  end
  body_lines << ''
  body_lines << 'Введите номер (#) для просмотра карточки.'

  send_to_max_chat(body_lines.join("\n"), chat_id, attachments: max_contacts_search_input_keyboard)
end

def contacts_show_detail_from_search(chat_id, list_index)
  state = MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] }
  return false unless state && state[:mode] == 'contacts_search_results'

  ids = state[:ids] || []
  return false unless list_index >= 0 && list_index < ids.size

  record = ContactsService.find(ids[list_index])
  return false unless record

  send_to_max_chat(
    ContactsService.detail_text(record),
    chat_id,
    attachments: max_contacts_detail_keyboard(record, 'contacts:back_search')
  )
  true
end

def devices_show_node(chat_id, path)
  node = DevicesInfoService.node_by_path(path)
  unless node
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
    send_to_max_chat('Раздел не найден.', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
    return
  end

  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'devices_tree', path: path } }

  if node[:text]
    body = "📘 #{node[:title]}\n\n#{node[:text].strip}"
    send_to_max_chat(body, chat_id, attachments: max_devices_node_keyboard(path))
  else
    send_to_max_chat("📚 #{node[:title]} — выберите:", chat_id, attachments: max_devices_node_keyboard(path))
  end
end

def max_sheets_tasks_keyboard(current_date, tasks = nil, viewing_name: nil, subscribed_name: nil)
  rows = [
    [{ text: '← Предыдущий день', payload: 'sheets:day:prev' }, { text: 'Следующий день →', payload: 'sheets:day:next' }],
    [{ text: 'Сегодня', payload: 'sheets:day:today' }, { text: 'Выбрать день', payload: 'sheets:day:pick' }]
  ]

  if viewing_name
    if subscribed_name == viewing_name
      rows << [{ text: '🔕 Отписаться от уведомлений', payload: 'sheets:unsubscribe' }]
    else
      label = subscribed_name ? "🔔 Переподписаться на #{viewing_name}" : '🔔 Подписаться на уведомления'
      rows << [{ text: label, payload: 'sheets:subscribe' }]
    end
  end

  rows << [{ text: 'Обновить', payload: 'sheets:refresh' }, { text: 'К списку людей', payload: 'sheets:pick_person' }]

  if tasks && YadiskService.enabled?
    photo_buttons = []
    tasks.each_with_index do |t, i|
      next unless SheetsService.extract_address_from_task(t[:task])

      photo_buttons << { text: "📷 #{t[:time]}", payload: "sheets:photo:#{i}" }
    end
    photo_buttons.each_slice(2) { |pair| rows << pair }
  end

  rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def max_sheets_day_picker_keyboard(dates)
  rows = dates.each_with_index.map do |d, idx|
    weekday = %w[Вс Пн Вт Ср Чт Пт Сб][d.wday]
    [{ text: "#{weekday} #{d.strftime('%d.%m')}", payload: "sheets:setday:#{idx}" }]
  end
  rows << [{ text: 'Назад', payload: 'sheets:back_to_tasks' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def sheets_format_day(name, date)
  weekday = %w[Воскресенье Понедельник Вторник Среда Четверг Пятница Суббота][date.wday]
  header = "📅 #{weekday}, #{date.strftime('%d.%m.%Y')} — #{name}"
  tasks = SheetsService.tasks_for(name, date)
  if tasks.empty?
    "#{header}\n\nЗаданий нет."
  else
    body = tasks.map { |t| "🕗 #{t[:time]}\n    #{t[:task]}" }.join("\n\n")
    "#{header}\n\n#{body}"
  end
end

def sheets_show_day(chat_id, name, date, user_id: nil)
  tasks = SheetsService.tasks_for(name, date)
  subscribed = user_id ? UserProfiles.name_for(user_id) : nil
  send_to_max_chat(
    sheets_format_day(name, date),
    chat_id,
    attachments: max_sheets_tasks_keyboard(date, tasks, viewing_name: name, subscribed_name: subscribed)
  )
end

def max_open_sheets(chat_id, user_id)
  unless SheetsService.enabled?
    send_to_max_chat('Модуль заданий не настроен.', chat_id, attachments: max_main_menu_keyboard)
    return
  end

  if SheetsService.parse_current.nil?
    send_to_max_chat('Загружаю расписание...', chat_id)
    SheetsService.refresh(force: true)
  end

  people = SheetsService.people
  if people.empty?
    send_to_max_chat('Не удалось прочитать расписание из таблицы.', chat_id, attachments: max_main_menu_keyboard)
    return
  end

  subscribed = user_id ? UserProfiles.name_for(user_id) : nil
  UserProfiles.update_chat_id(user_id, chat_id) if user_id && subscribed

  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_pick_name', user_id: user_id } }
  hint = subscribed ? "\nВаши уведомления: #{subscribed}" : "\nЧтобы получать уведомления — войдите в своё расписание и нажмите «Подписаться»."
  send_to_max_chat("Выберите чьё расписание посмотреть:#{hint}", chat_id, attachments: max_sheets_people_keyboard(people, subscribed))
end

YADISK_DRILL_PAGE_SIZE = 10

def max_yadisk_drill_keyboard(subfolders, page: 0)
  total = subfolders.size
  page_count = [(total + YADISK_DRILL_PAGE_SIZE - 1) / YADISK_DRILL_PAGE_SIZE, 1].max
  page = 0 if page < 0
  page = page_count - 1 if page >= page_count
  start_idx = page * YADISK_DRILL_PAGE_SIZE
  slice = subfolders[start_idx, YADISK_DRILL_PAGE_SIZE] || []

  rows = slice.each_with_index.map do |path, i|
    global_idx = start_idx + i
    label = path.to_s.split('/').last.to_s
    [{ text: "📁 #{label}", payload: "ydisk:drill:#{global_idx}" }]
  end

  if page_count > 1
    nav = []
    nav << { text: '← Пред.', payload: 'ydisk:drill_page:prev' } if page > 0
    nav << { text: "#{page + 1}/#{page_count}", payload: 'ydisk:drill_page:noop' }
    nav << { text: 'След. →', payload: 'ydisk:drill_page:next' } if page < page_count - 1
    rows << nav
  end

  rows << [{ text: '➕ Создать подпапку', payload: 'ydisk:create_sub' }]
  rows << [{ text: 'Искать снова', payload: 'ydisk:retry' }, { text: 'Назад', payload: 'Назад' }]
  rows << [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
  ArshinService.max_inline_keyboard(rows)
end

def arshin_item_to_pdf_data(item, year_fallback: nil, serial_override: nil)
  serial = (serial_override || item['mi_number']).to_s
  year = (item['_year'] || year_fallback).to_s
  {
    vri_id: (item['vri_id'] || item['id']).to_s.strip,
    serial: serial,
    year: year,
    mit_notation: item['mit_notation'].to_s,
    mit_title: item['mit_title'].to_s,
    org_title: item['org_title'].to_s,
    verification_date: item['verification_date'].to_s,
    valid_date: item['valid_date'].to_s,
    result_docnum: item['result_docnum'].to_s,
    applicability: item['applicability'] == true ? 'Да' : 'Нет',
    registry_url: ArshinService.registry_link_for_serial(serial, year: year.empty? ? nil : year)
  }
end

def arshin_pdf_base_name(arshin_item)
  serial = arshin_item[:serial].to_s.strip
  date = arshin_item[:verification_date].to_s.strip.tr('.', '-')
  vri = arshin_item[:vri_id].to_s.strip
  base =
    if !serial.empty? && !date.empty?
      "Поверка_#{serial}_#{date}"
    elsif !serial.empty? && !vri.empty?
      "Поверка_#{serial}_#{vri}"
    elsif !vri.empty?
      "Поверка_#{vri}"
    else
      "Поверка_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    end
  base.gsub(/[\\\/:\*\?"<>|]/, '_')
end

def start_arshin_snapshot_flow(chat_id, arshin_item, back_keyboard: nil)
  unless YadiskService.enabled?
    send_to_max_chat('Яндекс.Диск не настроен (YANDEX_DISK_TOKEN).', chat_id, attachments: back_keyboard)
    return
  end

  send_to_max_chat('📄 Формирую PDF с данными поверки...', chat_id)
  base_name = arshin_pdf_base_name(arshin_item)
  path, err = VerificationPdfService.generate(arshin_item, filename: base_name)
  if path.nil?
    send_to_max_chat("❌ Не удалось сформировать документ: #{err || 'unknown'}", chat_id, attachments: back_keyboard)
    return
  end
  filename = File.basename(path)
  warn_suffix = err ? " (с предупреждением: #{err})" : ''

  pending_snapshot_set(chat_id, path: path, filename: filename, vri_id: arshin_item[:vri_id].to_s)

  root = YadiskService.top_level_folders
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search', root_folders: root } }
  hint = "Документ готов (#{filename})#{warn_suffix}. Выберите папку на Я.Диске или введите часть адреса/фамилии для поиска:"
  if root.empty?
    send_to_max_chat(hint, chat_id, attachments: max_yadisk_search_keyboard)
  else
    send_to_max_chat(hint, chat_id, attachments: max_yadisk_root_keyboard(root))
  end
end

def yadisk_open_folder(chat_id, folder, sheets_context: nil)
  subs = YadiskService.subfolders(folder)
  has_snap = pending_snapshot?(chat_id)
  if subs.empty?
    state_data = { mode: 'yadisk_upload', folder: folder, count: 0 }
    state_data[:sheets_context] = sheets_context if sheets_context
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state_data }
    next_info = sheets_next_task_with_address(sheets_context)
    msg =
      if has_snap
        "Папка: #{YadiskService.folder_display_name(folder)}\nНажмите «Положить PDF сюда», либо пришлите фото."
      else
        "Папка: #{YadiskService.folder_display_name(folder)}\nПрисылайте фото одно за другим."
      end
    send_to_max_chat(
      msg,
      chat_id,
      attachments: max_yadisk_upload_keyboard(next_info, has_pending_snapshot: has_snap)
    )
  else
    state_data = { mode: 'yadisk_drill', folder: folder, subs: subs, page: 0 }
    state_data[:sheets_context] = sheets_context if sheets_context
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state_data }
    page_count = [(subs.size + YADISK_DRILL_PAGE_SIZE - 1) / YADISK_DRILL_PAGE_SIZE, 1].max
    hint = page_count > 1 ? "\nСтраница 1 из #{page_count}." : ''
    send_to_max_chat(
      "Папка «#{YadiskService.folder_display_name(folder)}» содержит #{subs.size} подпапок.#{hint}\nВыберите подпапку или создайте новую:",
      chat_id,
      attachments: max_yadisk_drill_keyboard(subs, page: 0)
    )
  end
end

def max_route_photo_for_task(chat_id, name, date, task_index)
  tasks = SheetsService.tasks_for(name, date)
  task = tasks[task_index]
  return false unless task

  query = SheetsService.extract_address_from_task(task[:task])
  return false unless query

  sheets_context = { name: name, date: date.iso8601, task_index: task_index }

  folders = YadiskService.search(query)
  if folders.empty?
    state_data = { mode: 'yadisk_not_found', query: query, sheets_context: sheets_context }
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state_data }
    send_to_max_chat("Искал «#{query}», ничего не найдено.", chat_id, attachments: max_yadisk_notfound_keyboard)
  elsif folders.size == 1
    yadisk_open_folder(chat_id, folders.first, sheets_context: sheets_context)
  else
    state_data = { mode: 'yadisk_choose', folders: folders, page: 0, sheets_context: sheets_context }
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state_data }
    page_count = ((folders.size + YADISK_PAGE_SIZE - 1) / YADISK_PAGE_SIZE)
    hint = page_count > 1 ? "\nСтраница 1 из #{page_count}." : ''
    send_to_max_chat("По «#{query}» найдено #{folders.size} папок.#{hint}\nВыберите:", chat_id, attachments: max_yadisk_folders_keyboard(folders, page: 0))
  end
  true
end

def max_calculations_menu_keyboard
  ArshinService.max_inline_keyboard([
    [{ text: 'Расчёт тепловой нагрузки', payload: 'calc:heat_load' }],
    [{ text: 'Расчёт дроссельной диафрагмы', payload: 'calc:diaphragm' }],
    [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
  ])
end

def max_arshin_year_keyboard
  ArshinService.max_arshin_year_keyboard
end

def max_arshin_org_keyboard
  ArshinService.max_arshin_org_keyboard
end

def arshin_form_normalize(form)
  ArshinService.arshin_form_normalize(form)
end

def max_arshin_form_keyboard(form = {}, arshin_items_count: 0)
  ArshinService.max_arshin_form_keyboard(form, arshin_items_count: arshin_items_count)
end

def max_volume_form_keyboard(form = {})
  VolumeCalcService.max_volume_form_keyboard(form)
end

def max_diaphragm_form_keyboard(form = {})
  VolumeCalcService.max_diaphragm_form_keyboard(form)
end

def max_message_key(upd, chat_id)
  mid = upd.dig('message', 'body', 'mid') || upd.dig('message', 'body', 'id')
  seq = upd.dig('message', 'body', 'seq') || upd.dig('message', 'body', 'sequence')
  ts = upd['timestamp'] || upd.dig('message', 'timestamp')
  return nil if mid.nil? && seq.nil? && ts.nil?

  "#{chat_id}:#{mid}:#{seq}:#{ts}"
end

def max_user_id_from_update(upd)
  update_type = upd['update_type'].to_s
  return upd.dig('user', 'user_id') if %w[user_added bot_started].include?(update_type)

  is_callback = update_type == 'message_callback' || !upd.dig('callback', 'callback_id').to_s.empty?
  if is_callback
    upd.dig('callback', 'user', 'user_id') || upd.dig('message', 'sender', 'user_id')
  else
    upd.dig('message', 'sender', 'user_id') || upd.dig('callback', 'user', 'user_id')
  end
end

def max_allowed_user_ids
  env_ids = ENV['MAX_ALLOWED_USER_IDS'].to_s.split(',').map(&:strip).reject(&:empty?)
  (env_ids + MaxUsersLog.all.keys.map(&:to_s)).uniq
end

def max_user_allowed?(user_id)
  uid = user_id.to_s.strip
  return false if uid.empty?

  max_allowed_user_ids.include?(uid)
end

def max_reject_unauthorized(chat_id, user_id)
  max_log("MAX unauthorized user_id=#{user_id.inspect} chat_id=#{chat_id}")
  send_to_max_chat('Доступ к боту не предоставлен.', chat_id)
end

def max_chat_id_for_dialog_event(upd)
  upd['chat_id'] ||
    upd.dig('chat', 'chat_id') ||
    upd.dig('chat', 'id') ||
    upd.dig('dialog', 'chat_id')
end

def max_log_identity(upd, chat_id, note = nil)
  return unless MAX_LOG_IDENTITY

  update_type = upd['update_type'].to_s
  user_id = max_user_id_from_update(upd)
  message = "MAX identity type=#{update_type} chat_id=#{chat_id} user_id=#{user_id.inspect}"
  message += " note=#{note}" if note
  max_log(message)
end

def max_send_main_menu(chat_id)
  send_to_max_chat('Выберите действие:', chat_id, attachments: max_main_menu_keyboard)
end

def max_send_main_menu_fallback(chat_id)
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES.delete(chat_id) }
  pending_snapshot_clear(chat_id)
  max_send_main_menu(chat_id)
end

def yadisk_reopen_search(chat_id)
  root = YadiskService.top_level_folders
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search', root_folders: root } }
  if root.empty?
    send_to_max_chat('Введите часть адреса или фамилии для поиска папки на Я.Диске:', chat_id, attachments: max_yadisk_search_keyboard)
  else
    send_to_max_chat('Выберите папку или введите часть адреса/фамилии для поиска:', chat_id, attachments: max_yadisk_root_keyboard(root))
  end
end

def handle_back_nav(state, chat_id, user_id)
  mode = state && state[:mode].to_s

  case mode
  when 'waiting_arshin_value'
    form = arshin_form_normalize(state[:form] || {})
    new_state = { mode: 'arshin_form', form: form }
    new_state[:arshin_items] = state[:arshin_items] if state[:arshin_items]
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = new_state }
    count = (state[:arshin_items] || []).size
    send_to_max_chat('АРШИН: форма поиска.', chat_id, attachments: max_arshin_form_keyboard(form, arshin_items_count: count))

  when 'volume_form', 'diaphragm_form'
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'calculations_menu' } }
    send_to_max_chat('Выберите расчёт:', chat_id, attachments: max_calculations_menu_keyboard)

  when 'waiting_volume_value'
    form = volume_form_normalize(state[:form] || {})
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'volume_form', form: form } }
    send_to_max_chat('Расчет по объемам: форма ввода.', chat_id, attachments: max_volume_form_keyboard(form))

  when 'waiting_diaphragm_value'
    form = VolumeCalcService.diaphragm_form_normalize(state[:form] || {})
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'diaphragm_form', form: form } }
    send_to_max_chat('Расчёт дроссельной диафрагмы: форма ввода.', chat_id, attachments: max_diaphragm_form_keyboard(form))

  when 'sheets_tasks'
    people = SheetsService.people
    subscribed = user_id ? UserProfiles.name_for(user_id) : nil
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_pick_name' } }
    send_to_max_chat('Выберите чьё расписание посмотреть:', chat_id, attachments: max_sheets_people_keyboard(people, subscribed))

  when 'billing_menu'
    has_sheets = SheetsService.enabled?
    has_billing = BillingService.enabled? && BillingService.user_allowed?(user_id)
    if has_sheets && has_billing
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'journals_menu' } }
      send_to_max_chat('Выберите журнал:', chat_id, attachments: max_journals_menu_keyboard(user_id))
    else
      max_send_main_menu_fallback(chat_id)
    end

  when 'billing_search', 'billing_new_month_confirm', 'billing_results'
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
    send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))

  when 'billing_card'
    matches = state[:matches] || []
    page = state[:page].to_i
    if matches.empty?
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
      send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
    else
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_results', matches: matches, page: page } }
      send_to_max_chat('Выберите:', chat_id, attachments: max_billing_results_keyboard(matches, page: page))
    end

  when 'billing_input_value'
    details = state[:details] || {}
    has_serial = !details[:serial].to_s.strip.empty?
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_card') }
    send_to_max_chat(billing_format_card(details), chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))

  when 'yadisk_choose', 'yadisk_drill', 'yadisk_not_found', 'yadisk_new_folder', 'yadisk_upload'
    pending_snapshot_clear(chat_id)
    yadisk_reopen_search(chat_id)

  when 'contacts_menu'
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
    send_to_max_chat('Выберите алгоритм:', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)

  when 'contacts_list', 'contacts_search', 'contacts_search_results'
    contacts_open_menu(chat_id, user_id: user_id)

  else
    # главное меню и его прямые дети (arshin_form, calculations_menu,
    # algorithms_menu, journals_menu, sheets_pick_name, yadisk_search) уходят домой
    max_send_main_menu_fallback(chat_id)
  end
end

def max_open_arshin_form(chat_id)
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'arshin_form', form: {} } }
  send_to_max_chat(
    "АРШИН: заполните нужные поля и нажмите 'Найти прибор'.\n" \
    "• Поверитель: организация, выполнившая поверку.\n" \
    "• Год: год поверки; если не задан, используется текущий год.\n" \
    "• Номер: заводской номер прибора (лучше как в документе, например 12-123124124).",
    chat_id,
    attachments: max_arshin_form_keyboard({})
  )
end
def max_welcome_after_start(_upd, chat_id)
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES.delete(chat_id.to_i) }
  max_send_main_menu(chat_id)
end

def max_handle_dialog_open_update(upd)
  update_type = upd['update_type'].to_s
  return false unless %w[user_added bot_started].include?(update_type)

  chat_id = max_chat_id_for_dialog_event(upd)
  return false if chat_id.nil? || chat_id.to_s.empty?
  user_id = max_user_id_from_update(upd)

  max_log("MAX dialog open: type=#{update_type} chat_id=#{chat_id}") if MAX_DEBUG
  max_log_identity(upd, chat_id, 'dialog_open')
  unless max_user_allowed?(user_id)
    max_reject_unauthorized(chat_id, user_id)
    return true
  end

  MaxUsersLog.record(upd, chat_id: chat_id)
  max_welcome_after_start(upd, chat_id)
  true
end

def arshin_lookup_by_form(form)
  ArshinService.arshin_lookup_by_form(form)
end

def volume_form_normalize(form)
  VolumeCalcService.volume_form_normalize(form)
end

def volume_calculate_by_form(form)
  VolumeCalcService.volume_calculate_by_form(form)
end

def max_open_diaphragm_form(chat_id)
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'diaphragm_form', form: {} } }
  send_to_max_chat(
    "Расчёт дроссельной диафрагмы: заполните поля и нажмите 'Рассчитать диафрагму'.\n" \
    "Изменяемые значения:\n" \
    "• Перепад давления\n" \
    "• Нагрузка на отопление",
    chat_id,
    attachments: max_diaphragm_form_keyboard({})
  )
end

def max_open_volume_form(chat_id)
  MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'volume_form', form: {} } }
  send_to_max_chat(
    "Расчет по объемам: заполните поля и нажмите 'Рассчитать Qот'.\n" \
    "Изменяемые значения:\n" \
    "• Н, м - высота\n" \
    "• V, куб.м\n" \
    "• q, ккал/куб.м час град\n" \
    "• t, вн.\n" \
    "• V подвал",
    chat_id,
    attachments: max_volume_form_keyboard({})
  )
end

def process_max_update(chat_id, text_raw, message_key = nil, user_id: nil)
  text = text_raw.to_s.gsub("\r\n", "\n").gsub("\r", "\n").strip

  if message_key
    now = Time.now.to_i
    already_processed = MAX_PROCESSED_MUTEX.synchronize do
      prev = MAX_PROCESSED_KEYS[message_key]
      if prev && (now - prev) < MAX_PROCESSED_TTL_SECONDS
        true
      else
        MAX_PROCESSED_KEYS[message_key] = now
        MAX_PROCESSED_KEYS.shift while MAX_PROCESSED_KEYS.size > 4000 if MAX_PROCESSED_KEYS.size > 5000
        false
      end
    end
    return if already_processed
  end

  state = MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] }

  case text
  when /\A\/?start\z/i, /\Aначать\z/i, /\A(🏠\s*)?главное меню\z/i, /\A(🏠\s*)?в главное меню\z/i
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES.delete(chat_id) }
    pending_snapshot_clear(chat_id)
    max_send_main_menu(chat_id)
    return
  when /\Aназад\z/i
    handle_back_nav(state, chat_id, user_id)
    return
  when /\Aповерка приборов(?:\s+в\s*аршин)?\z/i, /\Aаршин(?:\s*api)?\z/i
    max_open_arshin_form(chat_id)
    return
  when /\Aрасч[её]ты\z/i
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'calculations_menu' } }
    send_to_max_chat('Выберите расчёт:', chat_id, attachments: max_calculations_menu_keyboard)
    return
  when /\Acalc:heat_load\z/i, /\Aрасч[её]т тепловой нагрузки\z/i, /\Aрасчет по объемам\z/i, /\Aрасч[её]т по объемам\z/i
    max_open_volume_form(chat_id)
    return
  when /\Acalc:diaphragm\z/i, /\Aрасч[её]т дроссельной диафрагмы\z/i
    max_open_diaphragm_form(chat_id)
    return
  when /\Aалгоритмы\z/i
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
    send_to_max_chat('Выберите алгоритм:', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
    return
  when /\Acontacts:menu\z/i, /\Aконтакты потребителей\z/i
    contacts_open_menu(chat_id, user_id: user_id)
    return
  when /\Aзагрузка фото\z/i
    unless YadiskService.enabled?
      send_to_max_chat('Яндекс.Диск не настроен.', chat_id, attachments: max_main_menu_keyboard)
      return
    end
    pending_snapshot_clear(chat_id)
    root = YadiskService.top_level_folders
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search', root_folders: root } }
    if root.empty?
      send_to_max_chat('Введите часть адреса или фамилии для поиска папки на Я.Диске:', chat_id, attachments: max_yadisk_search_keyboard)
    else
      send_to_max_chat("Выберите папку или введите часть адреса/фамилии для поиска:", chat_id, attachments: max_yadisk_root_keyboard(root))
    end
    return
  when /\Aэлектронный журнал\z/i, /\Aзадани[яй]( на день)?\z/i
    max_open_sheets(chat_id, user_id)
    return
  when /\Aэлектронные журналы\z/i
    has_sheets = SheetsService.enabled?
    has_billing = BillingService.enabled? && BillingService.user_allowed?(user_id)
    available = [has_sheets, has_billing].count(true)

    if available.zero?
      send_to_max_chat('Журналы не настроены.', chat_id, attachments: max_main_menu_keyboard)
    elsif available == 1
      if has_sheets
        max_open_sheets(chat_id, user_id)
      else
        MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
        send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
      end
    else
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'journals_menu' } }
      send_to_max_chat('Выберите журнал:', chat_id, attachments: max_journals_menu_keyboard(user_id))
    end
    return
  when /\Aгвс биллинг\z/i
    unless BillingService.enabled? && BillingService.user_allowed?(user_id)
      send_to_max_chat('Доступ к ГВС биллингу не предоставлен.', chat_id, attachments: max_main_menu_keyboard)
      return
    end
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
    send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
    return
  end

  if state && state[:mode] == 'arshin_form'
    form = arshin_form_normalize(state[:form] || {})

    case text
    when /\Aarshin:set:org\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'waiting_arshin_value', field: 'org_title', form: form } }
      send_to_max_chat(
        "Поверитель (кто выполнял поверку):\n" \
        "• выберите поверителя кнопкой\n" \
        "• или введите свою организацию как в документе\n" \
        "• '-' чтобы очистить поле",
        chat_id,
        attachments: max_arshin_org_keyboard
      )
      return
    when /\Aarshin:set:year\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'waiting_arshin_value', field: 'year', form: form } }
      send_to_max_chat(
        "Год поверки:\n" \
        "• выберите год кнопкой или введите вручную (например 2026)\n" \
        "• если поле пустое, при поиске будет использован текущий год\n" \
        "• '-' чтобы очистить поле",
        chat_id,
        attachments: max_arshin_year_keyboard
      )
      return
    when /\Aarshin:set:number\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'waiting_arshin_value', field: 'mi_number', form: form } }
      send_to_max_chat(
        "Номер прибора:\n" \
        "• вводите номер точно как в документе (например 12-123124124)\n" \
        "• если не найдёт, бот автоматически повторит поиск по варианту без/с тире\n" \
        "• '-' чтобы очистить поле",
        chat_id
      )
      return
    when /\Aarshin:set:notation\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'waiting_arshin_value', field: 'mit_notation', form: form } }
      send_to_max_chat(
        "Тип/обозначение прибора:\n" \
        "• введите тип как в паспорте/свидетельстве (например СГВ-15, ВСКМ 90)\n" \
        "• можно вводить частично\n" \
        "• '-' чтобы очистить поле",
        chat_id
      )
      return
    when /\Aarshin:clear\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'arshin_form', form: {} } }
      send_to_max_chat('Поля очищены.', chat_id, attachments: max_arshin_form_keyboard({}))
      return
    when /\Aarshin:find\z/i
      result = ArshinService.lookup_by_form_detailed(form)
      items = result[:items] || []
      pdf_items = []
      if YadiskService.enabled?
        pdf_items = items
          .map { |it| arshin_item_to_pdf_data(it, year_fallback: result[:year]) }
          .reject { |d| d[:vri_id].empty? }
      end
      MAX_STATES_MUTEX.synchronize do
        new_state = { mode: 'arshin_form', form: form }
        new_state[:arshin_items] = pdf_items unless pdf_items.empty?
        MAX_USER_STATES[chat_id] = new_state
      end
      send_to_max_chat(result[:text], chat_id, attachments: max_arshin_form_keyboard(form, arshin_items_count: pdf_items.size))
      return
    when /\Aarshin:put_snap(?::(\d+))?\z/i
      idx = ::Regexp.last_match(1).to_i
      items = state[:arshin_items] || []
      arshin_item = items[idx]
      if arshin_item.nil? || arshin_item[:vri_id].to_s.strip.empty?
        send_to_max_chat('Сначала нажмите «Найти прибор» и выберите запись кнопкой.', chat_id, attachments: max_arshin_form_keyboard(form, arshin_items_count: items.size))
        return
      end
      start_arshin_snapshot_flow(chat_id, arshin_item, back_keyboard: max_arshin_form_keyboard(form, arshin_items_count: items.size))
      return
    else
      count = (state[:arshin_items] || []).size
      send_to_max_chat('Выберите действие кнопкой в форме АРШИН.', chat_id, attachments: max_arshin_form_keyboard(form, arshin_items_count: count))
      return
    end
  end

  if state && state[:mode] == 'waiting_arshin_value'
    if text.match?(/\Aназад\z/i)
      form = arshin_form_normalize(state[:form] || {})
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'arshin_form', form: form } }
      send_to_max_chat('АРШИН: форма поиска.', chat_id, attachments: max_arshin_form_keyboard(form))
      return
    end

    form = arshin_form_normalize(state[:form] || {})
    field = state[:field].to_s
    value = text.to_s.strip
    form[field] = (value == '-' || value.match?(/\Aочистить\z/i)) ? nil : value
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'arshin_form', form: form } }
    send_to_max_chat('Поле обновлено.', chat_id, attachments: max_arshin_form_keyboard(form))
    return
  end

  if state && state[:mode] == 'volume_form'
    form = volume_form_normalize(state[:form] || {})

    case text
    when /\Avolume:set:(h|v|q|t_vn|v_podval)\z/i
      field = ::Regexp.last_match(1).to_s
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'waiting_volume_value', field: field, form: form } }
      send_to_max_chat(VolumeCalcService.volume_field_prompt(field), chat_id)
      return
    when /\Avolume:clear\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'volume_form', form: {} } }
      send_to_max_chat('Поля очищены.', chat_id, attachments: max_volume_form_keyboard({}))
      return
    when /\Avolume:calc\z/i
      result_text = volume_calculate_by_form(form)
      send_to_max_chat(result_text, chat_id, attachments: max_volume_form_keyboard(form))
      return
    else
      send_to_max_chat('Выберите действие кнопкой в форме расчета.', chat_id, attachments: max_volume_form_keyboard(form))
      return
    end
  end

  if state && state[:mode] == 'waiting_volume_value'
    if text.match?(/\Aназад\z/i)
      form = volume_form_normalize(state[:form] || {})
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'volume_form', form: form } }
      send_to_max_chat('Расчет по объемам: форма ввода.', chat_id, attachments: max_volume_form_keyboard(form))
      return
    end

    form = volume_form_normalize(state[:form] || {})
    field = state[:field].to_s
    value = text.to_s.strip
    form[field] = (value == '-' || value.match?(/\Aочистить\z/i)) ? nil : value
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'volume_form', form: form } }
    send_to_max_chat('Поле обновлено.', chat_id, attachments: max_volume_form_keyboard(form))
    return
  end

  if state && state[:mode] == 'diaphragm_form'
    form = VolumeCalcService.diaphragm_form_normalize(state[:form] || {})

    case text
    when /\Adiaphragm:set:(pressure_drop|heating_load)\z/i
      field = ::Regexp.last_match(1).to_s
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'waiting_diaphragm_value', field: field, form: form } }
      send_to_max_chat(VolumeCalcService.diaphragm_field_prompt(field), chat_id)
      return
    when /\Adiaphragm:clear\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'diaphragm_form', form: {} } }
      send_to_max_chat('Поля очищены.', chat_id, attachments: max_diaphragm_form_keyboard({}))
      return
    when /\Adiaphragm:calc\z/i
      result_text = VolumeCalcService.diaphragm_calculate_by_form(form)
      send_to_max_chat(result_text, chat_id, attachments: max_diaphragm_form_keyboard(form))
      return
    else
      send_to_max_chat('Выберите действие кнопкой в форме расчета.', chat_id, attachments: max_diaphragm_form_keyboard(form))
      return
    end
  end

  if state && state[:mode] == 'waiting_diaphragm_value'
    if text.match?(/\Aназад\z/i)
      form = VolumeCalcService.diaphragm_form_normalize(state[:form] || {})
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'diaphragm_form', form: form } }
      send_to_max_chat('Расчёт дроссельной диафрагмы: форма ввода.', chat_id, attachments: max_diaphragm_form_keyboard(form))
      return
    end

    form = VolumeCalcService.diaphragm_form_normalize(state[:form] || {})
    field = state[:field].to_s
    value = text.to_s.strip
    form[field] = (value == '-' || value.match?(/\Aочистить\z/i)) ? nil : value
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'diaphragm_form', form: form } }
    send_to_max_chat('Поле обновлено.', chat_id, attachments: max_diaphragm_form_keyboard(form))
    return
  end

  if state && state[:mode] == 'calculations_menu'
    send_to_max_chat('Выберите расчёт кнопкой.', chat_id, attachments: max_calculations_menu_keyboard)
    return
  end

  if state && state[:mode] == 'algorithms_menu'
    case text
    when /\Adevices:root\z/i
      devices_show_node(chat_id, [])
      return
    when /\Aalgo:([a-z0-9_]+)\z/i
      algo_key = ::Regexp.last_match(1).to_s.downcase
      if AlgorithmsService.algorithm_exists?(algo_key)
        MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algo_steps', algo: algo_key, step: 0 } }
        send_to_max_chat(
          AlgorithmsService.algorithm_step_text(algo_key, 0),
          chat_id,
          attachments: AlgorithmsService.algorithm_step_keyboard(algo_key, 0)
        )
      else
        send_to_max_chat('Алгоритм не найден. Выберите вариант из списка.', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
      end
      return
    when /\Aалгоритмы\z/i, /\Aalgo:menu\z/i
      send_to_max_chat('Выберите алгоритм:', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
      return
    else
      send_to_max_chat('Выберите алгоритм кнопкой.', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
      return
    end
  end

  if state && state[:mode] == 'contacts_menu'
    case text
    when /\Acontacts:cat:([a-z_]+)(?::page:(\d+))?\z/i
      cat = ::Regexp.last_match(1).to_s
      page = ::Regexp.last_match(2).to_i
      unless ContactsService.categories.include?(cat)
        send_to_max_chat('Категория не найдена.', chat_id, attachments: max_contacts_menu_keyboard(user_id))
        return
      end
      contacts_show_list_page(chat_id, cat, page)
      return
    when /\Acontacts:search\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'contacts_search' } }
      send_to_max_chat('Введите часть наименования, адреса, ФИО или телефона:', chat_id, attachments: max_contacts_search_input_keyboard)
      return
    when /\Acontacts:sync\z/i
      unless contacts_admin?(user_id)
        send_to_max_chat('Обновление доступно только админам.', chat_id, attachments: max_contacts_menu_keyboard(user_id))
        return
      end
      send_to_max_chat('🔄 Скачиваю и обновляю контакты...', chat_id)
      ok, summary = ContactsSyncService.sync(force: true)
      if ok
        lines = ['✅ Контакты обновлены.']
        summary.each { |cat, info| lines << "  #{ContactsService.category_label(cat)}: #{info[:ok] ? "#{info[:count]} записей" : "ошибка — #{info[:error]}"}" }
        send_to_max_chat(lines.join("\n"), chat_id, attachments: max_contacts_menu_keyboard(user_id))
      else
        send_to_max_chat("❌ Ошибка обновления: #{summary}", chat_id, attachments: max_contacts_menu_keyboard(user_id))
      end
      return
    else
      send_to_max_chat('Выберите кнопкой.', chat_id, attachments: max_contacts_menu_keyboard(user_id))
      return
    end
  end

  if state && state[:mode] == 'contacts_list'
    category = state[:category].to_s
    page = state[:page].to_i
    total = state[:total].to_i
    page_count = [(total + MAX_CONTACTS_PAGE_SIZE - 1) / MAX_CONTACTS_PAGE_SIZE, 1].max

    case text
    when /\Acontacts:list_page:(prev|next|noop)\z/i
      direction = ::Regexp.last_match(1)
      return if direction == 'noop'

      new_page = direction == 'prev' ? [page - 1, 0].max : [page + 1, page_count - 1].min
      contacts_show_list_page(chat_id, category, new_page)
      return
    when /\A(\d+)\z/
      number = ::Regexp.last_match(1).to_i
      if number >= 1 && number <= total
        ok = contacts_show_detail_from_list(chat_id, number - 1)
        unless ok
          send_to_max_chat('Запись не найдена. Введите номер из текущей страницы.', chat_id, attachments: max_contacts_list_keyboard(category, page, total))
        end
        return
      end
      send_to_max_chat("Номер должен быть от 1 до #{total}.", chat_id, attachments: max_contacts_list_keyboard(category, page, total))
      return
    when /\Acontacts:cat:([a-z_]+)(?::page:(\d+))?\z/i
      target = ::Regexp.last_match(1).to_s
      target_page = ::Regexp.last_match(2).to_i
      contacts_show_list_page(chat_id, target, target_page)
      return
    end
    send_to_max_chat('Введите номер записи или используйте кнопки.', chat_id, attachments: max_contacts_list_keyboard(category, page, total))
    return
  end

  if state && state[:mode] == 'contacts_search'
    if text.to_s.strip.length < 2
      send_to_max_chat('Введите минимум 2 символа.', chat_id, attachments: max_contacts_search_input_keyboard)
      return
    end
    contacts_show_search_results(chat_id, text.to_s.strip)
    return
  end

  if state && state[:mode] == 'contacts_search_results'
    case text
    when /\A(\d+)\z/
      number = ::Regexp.last_match(1).to_i
      ids = state[:ids] || []
      if number >= 1 && number <= ids.size
        ok = contacts_show_detail_from_search(chat_id, number - 1)
        unless ok
          send_to_max_chat('Запись не найдена.', chat_id, attachments: max_contacts_search_input_keyboard)
        end
        return
      end
      send_to_max_chat("Номер должен быть от 1 до #{ids.size}.", chat_id, attachments: max_contacts_search_input_keyboard)
      return
    when /\Acontacts:back_search\z/i
      contacts_show_search_results(chat_id, state[:query].to_s)
      return
    else
      contacts_show_search_results(chat_id, text.to_s.strip) if text.to_s.strip.length >= 2
      return
    end
  end

  if state && state[:mode] == 'devices_tree'
    path = state[:path] || []

    case text
    when /\Adevices:go:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      devices_show_node(chat_id, path + [idx])
      return
    when /\Adevices:up\z/i
      devices_show_node(chat_id, path[0...-1])
      return
    when /\Adevices:root\z/i
      devices_show_node(chat_id, [])
      return
    when /\Aalgo:menu\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
      send_to_max_chat('Выберите алгоритм:', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
      return
    end
    devices_show_node(chat_id, path)
    return
  end

  if state && state[:mode] == 'algo_steps'
    step = state[:step].to_i
    algo_key = state[:algo].to_s

    case text
    when /\Aalgo:([a-z0-9_]+):next\z/i
      key = ::Regexp.last_match(1).to_s.downcase
      key = algo_key if key.empty?
      steps_count = AlgorithmsService.algorithm_steps(key).size
      if steps_count <= 0
        send_to_max_chat('Алгоритм не найден. Выберите вариант из списка.', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
        MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
        return
      end
      step = [step + 1, steps_count - 1].min
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algo_steps', algo: key, step: step } }
      send_to_max_chat(
        AlgorithmsService.algorithm_step_text(key, step),
        chat_id,
        attachments: AlgorithmsService.algorithm_step_keyboard(key, step)
      )
      return
    when /\Aalgo:([a-z0-9_]+):prev\z/i
      key = ::Regexp.last_match(1).to_s.downcase
      key = algo_key if key.empty?
      unless AlgorithmsService.algorithm_exists?(key)
        send_to_max_chat('Алгоритм не найден. Выберите вариант из списка.', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
        MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
        return
      end
      step = [step - 1, 0].max
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algo_steps', algo: key, step: step } }
      send_to_max_chat(
        AlgorithmsService.algorithm_step_text(key, step),
        chat_id,
        attachments: AlgorithmsService.algorithm_step_keyboard(key, step)
      )
      return
    when /\Aalgo:menu\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'algorithms_menu' } }
      send_to_max_chat('Выберите алгоритм:', chat_id, attachments: AlgorithmsService.algorithms_menu_keyboard)
      return
    else
      send_to_max_chat(
        AlgorithmsService.algorithm_step_text(algo_key, step),
        chat_id,
        attachments: AlgorithmsService.algorithm_step_keyboard(algo_key, step)
      )
      return
    end
  end

  if state && state[:mode] == 'yadisk_search'
    root = state[:root_folders] || []
    root_page = state[:root_page].to_i
    root_page_count = [(root.size + YADISK_ROOT_PAGE_SIZE - 1) / YADISK_ROOT_PAGE_SIZE, 1].max

    case text
    when /\Aydisk:root:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      folder = root[idx]
      if folder
        yadisk_open_folder(chat_id, folder)
      else
        send_to_max_chat('Папка не найдена.', chat_id, attachments: max_yadisk_root_keyboard(root, page: root_page))
      end
      return
    when /\Aydisk:root_page:next\z/i
      new_page = [root_page + 1, root_page_count - 1].min
      MAX_STATES_MUTEX.synchronize do
        MAX_USER_STATES[chat_id] = state.merge(root_page: new_page)
      end
      send_to_max_chat("Страница #{new_page + 1} из #{root_page_count}:", chat_id, attachments: max_yadisk_root_keyboard(root, page: new_page))
      return
    when /\Aydisk:root_page:prev\z/i
      new_page = [root_page - 1, 0].max
      MAX_STATES_MUTEX.synchronize do
        MAX_USER_STATES[chat_id] = state.merge(root_page: new_page)
      end
      send_to_max_chat("Страница #{new_page + 1} из #{root_page_count}:", chat_id, attachments: max_yadisk_root_keyboard(root, page: new_page))
      return
    when /\Aydisk:root_page:noop\z/i
      return
    when /\Aydisk:retry\z/i
      send_to_max_chat('Введите новый запрос:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    when /\Aydisk:create\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_new_folder' } }
      send_to_max_chat('Введите название новой папки:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    end

    folders = YadiskService.search(text)
    if folders.empty?
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_not_found', query: text } }
      send_to_max_chat("По запросу «#{text}» ничего не найдено.", chat_id, attachments: max_yadisk_notfound_keyboard)
    elsif folders.size == 1
      yadisk_open_folder(chat_id, folders.first)
    else
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_choose', folders: folders, page: 0 } }
      page_count = ((folders.size + YADISK_PAGE_SIZE - 1) / YADISK_PAGE_SIZE)
      hint = page_count > 1 ? "\nСтраница 1 из #{page_count}. Уточните запрос чтобы сузить список." : ''
      send_to_max_chat("Найдено #{folders.size} папок.#{hint}\nВыберите:", chat_id, attachments: max_yadisk_folders_keyboard(folders, page: 0))
    end
    return
  end

  if state && state[:mode] == 'yadisk_not_found'
    case text
    when /\Aydisk:retry\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search' } }
      send_to_max_chat('Введите новый запрос:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    when /\Aydisk:create\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_new_folder' } }
      send_to_max_chat('Введите название новой папки:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    end
    send_to_max_chat('Выберите действие кнопкой.', chat_id, attachments: max_yadisk_notfound_keyboard)
    return
  end

  if state && state[:mode] == 'yadisk_choose'
    folders = state[:folders] || []
    page = state[:page].to_i
    page_count = ((folders.size + YADISK_PAGE_SIZE - 1) / YADISK_PAGE_SIZE)
    page_count = 1 if page_count < 1

    case text
    when /\Aydisk:pick:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      folder = folders[idx]
      if folder
        yadisk_open_folder(chat_id, folder, sheets_context: state[:sheets_context])
      else
        send_to_max_chat('Папка не найдена.', chat_id, attachments: max_yadisk_folders_keyboard(folders, page: page))
      end
      return
    when /\Aydisk:page:next\z/i
      new_page = [page + 1, page_count - 1].min
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_choose', folders: folders, page: new_page } }
      send_to_max_chat("Страница #{new_page + 1} из #{page_count}:", chat_id, attachments: max_yadisk_folders_keyboard(folders, page: new_page))
      return
    when /\Aydisk:page:prev\z/i
      new_page = [page - 1, 0].max
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_choose', folders: folders, page: new_page } }
      send_to_max_chat("Страница #{new_page + 1} из #{page_count}:", chat_id, attachments: max_yadisk_folders_keyboard(folders, page: new_page))
      return
    when /\Aydisk:page:noop\z/i
      return
    when /\Aydisk:retry\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search' } }
      send_to_max_chat('Введите новый запрос:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    when /\Aydisk:create\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_new_folder' } }
      send_to_max_chat('Введите название новой папки:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    end
    send_to_max_chat('Выберите папку кнопкой.', chat_id, attachments: max_yadisk_folders_keyboard(folders, page: page))
    return
  end

  if state && state[:mode] == 'yadisk_drill'
    subs = state[:subs] || []
    parent = state[:folder]
    page = state[:page].to_i
    page_count = [(subs.size + YADISK_DRILL_PAGE_SIZE - 1) / YADISK_DRILL_PAGE_SIZE, 1].max

    case text
    when /\Aydisk:drill:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      sub = subs[idx]
      if sub
        yadisk_open_folder(chat_id, sub, sheets_context: state[:sheets_context])
      else
        send_to_max_chat('Папка не найдена.', chat_id, attachments: max_yadisk_drill_keyboard(subs, page: page))
      end
      return
    when /\Aydisk:drill_page:next\z/i
      new_page = [page + 1, page_count - 1].min
      MAX_STATES_MUTEX.synchronize do
        MAX_USER_STATES[chat_id] = state.merge(page: new_page)
      end
      send_to_max_chat("Страница #{new_page + 1} из #{page_count}:", chat_id, attachments: max_yadisk_drill_keyboard(subs, page: new_page))
      return
    when /\Aydisk:drill_page:prev\z/i
      new_page = [page - 1, 0].max
      MAX_STATES_MUTEX.synchronize do
        MAX_USER_STATES[chat_id] = state.merge(page: new_page)
      end
      send_to_max_chat("Страница #{new_page + 1} из #{page_count}:", chat_id, attachments: max_yadisk_drill_keyboard(subs, page: new_page))
      return
    when /\Aydisk:drill_page:noop\z/i
      return
    when /\Aydisk:retry\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search' } }
      send_to_max_chat('Введите новый запрос:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    when /\Aydisk:create_sub\z/i
      new_state = { mode: 'yadisk_new_folder', parent: parent }
      new_state[:sheets_context] = state[:sheets_context] if state[:sheets_context]
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = new_state }
      send_to_max_chat("Введите название новой подпапки внутри «#{YadiskService.folder_display_name(parent)}»:", chat_id, attachments: max_yadisk_search_keyboard)
      return
    end

    send_to_max_chat('Выберите кнопкой.', chat_id, attachments: max_yadisk_drill_keyboard(subs, page: page))
    return
  end

  if state && state[:mode] == 'yadisk_new_folder'
    folder, err = YadiskService.create_folder(text, parent: state[:parent])
    if err
      send_to_max_chat("Ошибка: #{err}", chat_id, attachments: max_yadisk_notfound_keyboard)
      return
    end
    sheets_context = state[:sheets_context]
    new_state = { mode: 'yadisk_upload', folder: folder, count: 0 }
    new_state[:sheets_context] = sheets_context if sheets_context
    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = new_state }
    next_info = sheets_next_task_with_address(sheets_context)
    has_snap = pending_snapshot?(chat_id)
    tail = has_snap ? 'Нажмите «Положить PDF сюда», либо пришлите фото.' : 'Присылайте фото.'
    send_to_max_chat("Папка создана: #{YadiskService.folder_display_name(folder)}\n#{tail}", chat_id, attachments: max_yadisk_upload_keyboard(next_info, has_pending_snapshot: has_snap))
    return
  end

  if state && state[:mode] == 'yadisk_upload'
    has_snap = pending_snapshot?(chat_id)
    case text
    when /\Aydisk:retry\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'yadisk_search' } }
      send_to_max_chat('Введите новый запрос:', chat_id, attachments: max_yadisk_search_keyboard)
      return
    when /\Aydisk:create_sub_here\z/i
      parent = state[:folder]
      new_state = { mode: 'yadisk_new_folder', parent: parent }
      new_state[:sheets_context] = state[:sheets_context] if state[:sheets_context]
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = new_state }
      send_to_max_chat("Введите название новой подпапки внутри «#{YadiskService.folder_display_name(parent)}»:", chat_id, attachments: max_yadisk_search_keyboard)
      return
    when /\Aydisk:next_task\z/i
      ctx = state[:sheets_context]
      next_info = sheets_next_task_with_address(ctx)
      unless ctx && next_info
        send_to_max_chat('Следующих заданий с адресом нет.', chat_id, attachments: max_yadisk_upload_keyboard(nil, has_pending_snapshot: has_snap))
        return
      end
      date = Date.iso8601(ctx[:date].to_s) rescue Date.today
      max_route_photo_for_task(chat_id, ctx[:name].to_s, date, next_info[:index])
      return
    when /\Aydisk:putsnap\z/i
      snap = pending_snapshot_get(chat_id)
      unless snap
        next_info = sheets_next_task_with_address(state[:sheets_context])
        send_to_max_chat('PDF не найден (возможно, истёк срок).', chat_id, attachments: max_yadisk_upload_keyboard(next_info, has_pending_snapshot: false))
        return
      end
      folder = state[:folder]
      send_to_max_chat('⏳ Загружаю PDF...', chat_id)
      ok, dest, err = YadiskService.upload_file(folder, snap[:filename], snap[:path])
      if ok
        pending_snapshot_clear(chat_id)
        new_count = state[:count].to_i + 1
        MAX_STATES_MUTEX.synchronize do
          cur = MAX_USER_STATES[chat_id]
          if cur && cur[:mode] == 'yadisk_upload' && cur[:folder] == folder
            MAX_USER_STATES[chat_id] = cur.merge(count: new_count)
          end
        end
        next_info = sheets_next_task_with_address(state[:sheets_context])
        send_to_max_chat("✅ PDF положен в «#{YadiskService.folder_display_name(folder)}» как #{snap[:filename]}.", chat_id, attachments: max_yadisk_upload_keyboard(next_info, has_pending_snapshot: false))
      else
        next_info = sheets_next_task_with_address(state[:sheets_context])
        send_to_max_chat("❌ Не удалось загрузить PDF: #{err}", chat_id, attachments: max_yadisk_upload_keyboard(next_info, has_pending_snapshot: true))
      end
      return
    end
    next_info = sheets_next_task_with_address(state[:sheets_context])
    tail = has_snap ? 'Нажмите «Положить PDF сюда», либо пришлите фото.' : 'Присылайте фото.'
    send_to_max_chat("Текущая папка: #{YadiskService.folder_display_name(state[:folder])}\n#{tail}", chat_id, attachments: max_yadisk_upload_keyboard(next_info, has_pending_snapshot: has_snap))
    return
  end

  if state && state[:mode] == 'sheets_pick_name'
    people = SheetsService.people
    subscribed_here = user_id ? UserProfiles.name_for(user_id) : nil

    picked_name = nil
    if text =~ /\Asheets:who:(\d+)\z/i
      picked_name = people[::Regexp.last_match(1).to_i]
    else
      picked_name = people.find { |n| n.downcase == text.downcase }
    end

    unless picked_name
      send_to_max_chat('Выберите имя из списка кнопкой:', chat_id, attachments: max_sheets_people_keyboard(people, subscribed_here))
      return
    end

    date = Date.today
    dates = SheetsService.available_dates
    unless dates.include?(date)
      future = dates.select { |d| d >= date }
      date = future.first || dates.last || date
    end

    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_tasks', name: picked_name, date: date.iso8601 } }
    sheets_show_day(chat_id, picked_name, date, user_id: user_id)
    return
  end

  if state && state[:mode] == 'sheets_tasks'
    name = state[:name].to_s
    current = Date.iso8601(state[:date].to_s) rescue Date.today
    dates = SheetsService.available_dates

    case text
    when /\Asheets:day:today\z/i
      target = Date.today
      target = dates.select { |d| d >= target }.first || dates.last || target unless dates.include?(target)
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_tasks', name: name, date: target.iso8601 } }
      sheets_show_day(chat_id, name, target, user_id: user_id)
      return
    when /\Asheets:day:next\z/i
      idx = dates.index(current) || -1
      target = dates[idx + 1] || current
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_tasks', name: name, date: target.iso8601 } }
      sheets_show_day(chat_id, name, target, user_id: user_id)
      return
    when /\Asheets:day:prev\z/i
      idx = dates.index(current) || 0
      target = idx > 0 ? dates[idx - 1] : current
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_tasks', name: name, date: target.iso8601 } }
      sheets_show_day(chat_id, name, target, user_id: user_id)
      return
    when /\Asheets:day:pick\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_day_picker', name: name, date: current.iso8601 } }
      send_to_max_chat('Выберите день:', chat_id, attachments: max_sheets_day_picker_keyboard(dates))
      return
    when /\Asheets:refresh\z/i
      send_to_max_chat('Обновляю расписание...', chat_id)
      SheetsService.refresh(force: true)
      sheets_show_day(chat_id, name, current, user_id: user_id)
      return
    when /\Asheets:subscribe\z/i
      unless user_id
        sheets_show_day(chat_id, name, current, user_id: user_id)
        return
      end
      UserProfiles.set_name(user_id, name, chat_id: chat_id)
      JournalNotifyService.bind_max_user(user_id, name)
      send_to_max_chat("🔔 Подписка оформлена: #{name}.\nУведомления о вашей колонке в электронном журнале и задания в 8:00 (пн–пт).", chat_id)
      sheets_show_day(chat_id, name, current, user_id: user_id)
      return
    when /\Asheets:unsubscribe\z/i
      if user_id
        UserProfiles.clear(user_id)
        JournalNotifyService.unbind_max_user(user_id)
      end
      send_to_max_chat('🔕 Отписка выполнена. Уведомлений по журналу и утренних заданий больше не будет.', chat_id)
      sheets_show_day(chat_id, name, current, user_id: user_id)
      return
    when /\Asheets:pick_person\z/i
      max_open_sheets(chat_id, user_id)
      return
    when /\Asheets:photo:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      tasks = SheetsService.tasks_for(name, current)

      unless YadiskService.enabled?
        send_to_max_chat('Яндекс.Диск не настроен.', chat_id, attachments: max_sheets_tasks_keyboard(current, tasks, viewing_name: name, subscribed_name: user_id ? UserProfiles.name_for(user_id) : nil))
        return
      end

      task = tasks[idx]
      unless task && SheetsService.extract_address_from_task(task[:task])
        msg = task ? 'В этой задаче не нашёл адрес.' : 'Задача не найдена.'
        send_to_max_chat(msg, chat_id, attachments: max_sheets_tasks_keyboard(current, tasks, viewing_name: name, subscribed_name: user_id ? UserProfiles.name_for(user_id) : nil))
        return
      end

      max_route_photo_for_task(chat_id, name, current, idx)
      return
    end

    sheets_show_day(chat_id, name, current, user_id: user_id)
    return
  end

  if state && state[:mode] == 'sheets_day_picker'
    name = state[:name].to_s
    dates = SheetsService.available_dates

    case text
    when /\Asheets:setday:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      target = dates[idx]
      if target
        MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_tasks', name: name, date: target.iso8601 } }
        sheets_show_day(chat_id, name, target, user_id: user_id)
      else
        send_to_max_chat('День не найден.', chat_id, attachments: max_sheets_day_picker_keyboard(dates))
      end
      return
    when /\Asheets:back_to_tasks\z/i
      current = Date.iso8601(state[:date].to_s) rescue Date.today
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'sheets_tasks', name: name, date: current.iso8601 } }
      sheets_show_day(chat_id, name, current, user_id: user_id)
      return
    end

    send_to_max_chat('Выберите день кнопкой:', chat_id, attachments: max_sheets_day_picker_keyboard(dates))
    return
  end

  if state && state[:mode] == 'journals_menu'
    send_to_max_chat('Выберите журнал кнопкой.', chat_id, attachments: max_journals_menu_keyboard(user_id))
    return
  end

  if state && state[:mode] == 'billing_menu'
    case text
    when /\Abilling:search\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_search' } }
      send_to_max_chat('Введите часть имени абонента или адреса:', chat_id, attachments: max_billing_search_keyboard)
      return
    when /\Abilling:new_month_ask\z/i
      unless billing_can_create_month_in_bot?(user_id)
        send_to_max_chat('Доступ к данной функции вам не предоставлен.', chat_id, attachments: max_billing_menu_keyboard(user_id))
        return
      end
      current = BillingService.current_sheet
      next_name = current ? BillingService.next_month_name(current[:name]) : nil
      if current.nil? || next_name.nil?
        send_to_max_chat('Не смог определить текущий/следующий месяц.', chat_id, attachments: max_billing_menu_keyboard(user_id))
        return
      end
      send_to_max_chat(
        "Создать вкладку «#{next_name}» на основе «#{current[:name]}»?\n\n" \
        "• У объектов с введёнными текущими показаниями — они станут новыми конечными.\n" \
        "• У остальных конечные останутся прежними.\n" \
        "• Текущие показания в новом месяце будут очищены.",
        chat_id,
        attachments: max_billing_confirm_new_month_keyboard
      )
      return
    when /\Abilling:new_month_confirm\z/i
      unless billing_can_create_month_in_bot?(user_id)
        send_to_max_chat('Доступ к данной функции вам не предоставлен.', chat_id, attachments: max_billing_menu_keyboard(user_id))
        return
      end
      send_to_max_chat('Создаю следующий месяц, подожди...', chat_id)
      new_name, err = BillingService.create_next_month
      if err && !new_name
        send_to_max_chat("❌ #{err}", chat_id, attachments: max_billing_menu_keyboard(user_id))
      elsif err
        send_to_max_chat("⚠ #{err}", chat_id, attachments: max_billing_menu_keyboard(user_id))
      else
        send_to_max_chat("✅ Вкладка «#{new_name}» создана.", chat_id)
        creator_name = UserProfiles.get_name(user_id).to_s.strip
        creator_name = user_id.to_s if creator_name.empty?
        MaxNotifyService.notify_journal_event("📅 Создан новый месяц ГВС: «#{new_name}»\nКто создал: #{creator_name}")
        last_day = BillingService.end_of_month_for(new_name)
        billing_send_expiring_poverki(chat_id, until_date: last_day)
        send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
      end
      return
    when /\Abilling:menu\z/i
      send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
      return
    end
    send_to_max_chat('Выберите действие кнопкой.', chat_id, attachments: max_billing_menu_keyboard(user_id))
    return
  end

  if state && state[:mode] == 'billing_search'
    if text =~ /\Abilling:menu\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
      send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
      return
    end

    query = text.to_s.strip
    if query.empty? || query.start_with?('billing:')
      send_to_max_chat('Введите часть имени абонента или адреса:', chat_id, attachments: max_billing_search_keyboard)
      return
    end

    matches = BillingService.find_objects(query)
    if matches.empty?
      send_to_max_chat("По «#{query}» ничего не найдено. Попробуй другой запрос:", chat_id, attachments: max_billing_search_keyboard)
      return
    end

    MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_results', matches: matches, page: 0, query: query } }
    page_count = [(matches.size + BILLING_RESULTS_PAGE_SIZE - 1) / BILLING_RESULTS_PAGE_SIZE, 1].max
    hint = page_count > 1 ? "\nСтраница 1 из #{page_count}." : ''
    send_to_max_chat("Найдено #{matches.size} объектов.#{hint}\nВыберите:", chat_id, attachments: max_billing_results_keyboard(matches, page: 0))
    return
  end

  if state && state[:mode] == 'billing_results'
    matches = state[:matches] || []
    page = state[:page].to_i
    page_count = [(matches.size + BILLING_RESULTS_PAGE_SIZE - 1) / BILLING_RESULTS_PAGE_SIZE, 1].max

    case text
    when /\Abilling:pick:(\d+)\z/i
      idx = ::Regexp.last_match(1).to_i
      match = matches[idx]
      unless match
        send_to_max_chat('Объект не найден.', chat_id, attachments: max_billing_results_keyboard(matches, page: page))
        return
      end

      details = BillingService.object_details(match[:row])
      unless details
        send_to_max_chat('Не удалось прочитать карточку.', chat_id, attachments: max_billing_results_keyboard(matches, page: page))
        return
      end

      MAX_STATES_MUTEX.synchronize do
        MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_card', row: match[:row], details: details)
      end
      send_to_max_chat(billing_format_card(details), chat_id, attachments: max_billing_card_keyboard(has_serial: !details[:serial].to_s.strip.empty?))
      return
    when /\Abilling:page:next\z/i
      new_page = [page + 1, page_count - 1].min
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state.merge(page: new_page) }
      send_to_max_chat("Страница #{new_page + 1} из #{page_count}:", chat_id, attachments: max_billing_results_keyboard(matches, page: new_page))
      return
    when /\Abilling:page:prev\z/i
      new_page = [page - 1, 0].max
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state.merge(page: new_page) }
      send_to_max_chat("Страница #{new_page + 1} из #{page_count}:", chat_id, attachments: max_billing_results_keyboard(matches, page: new_page))
      return
    when /\Abilling:page:noop\z/i
      return
    when /\Abilling:search\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_search' } }
      send_to_max_chat('Введите часть имени абонента или адреса:', chat_id, attachments: max_billing_search_keyboard)
      return
    when /\Abilling:menu\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
      send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
      return
    end
    send_to_max_chat('Выберите кнопкой.', chat_id, attachments: max_billing_results_keyboard(matches, page: page))
    return
  end

  if state && state[:mode] == 'billing_card'
    details = state[:details] || {}
    has_serial = !details[:serial].to_s.strip.empty?

    case text
    when /\Abilling:enter_value\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_input_value') }
      send_to_max_chat('Введите текущие показания (число):', chat_id, attachments: max_billing_cancel_keyboard)
      return
    when /\Abilling:check_arshin\z/i
      if details[:serial].to_s.strip.empty?
        send_to_max_chat('У объекта нет заводского номера в таблице.', chat_id, attachments: max_billing_card_keyboard(has_serial: false))
        return
      end
      send_to_max_chat("Ищу в АРШИН по заводскому №#{details[:serial]}...", chat_id)
      item, err = ArshinService.find_by_serial(
        details[:serial],
        require_all_keywords: %w[счетчик вод],
        reject_keywords: %w[тепл газ электр энерги]
      )
      if err
        send_to_max_chat("❌ Ошибка АРШИН: #{err}", chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
      elsif item.nil?
        send_to_max_chat("🔎 В АРШИН по №#{details[:serial]} ничего не найдено.", chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
      else
        pdf_data = arshin_item_to_pdf_data(item, serial_override: details[:serial].to_s)
        vri_id = pdf_data[:vri_id]
        MAX_STATES_MUTEX.synchronize do
          cur = MAX_USER_STATES[chat_id]
          if cur && cur[:mode] == 'billing_card'
            MAX_USER_STATES[chat_id] = cur.merge(arshin_item: pdf_data)
          end
        end
        arshin_valid = item['valid_date'].to_s.strip
        arshin_verif = item['verification_date'].to_s.strip
        arshin_org = item['org_title'].to_s.strip
        arshin_doc = item['result_docnum'].to_s.strip
        arshin_applicable = item['applicability'] == true ? 'Да' : 'Нет'

        table_next = details[:poverka_next].to_s.strip
        d_table = BillingService.parse_flexible_date(table_next)
        d_arshin = BillingService.parse_flexible_date(arshin_valid)

        cmp_line =
          if d_table && d_arshin
            d_table == d_arshin ? '✅ Даты совпадают' : '⚠ Даты расходятся'
          elsif arshin_valid.empty?
            '⚠ В АРШИН нет даты окончания поверки'
          else
            'ℹ Не смог автоматически сравнить даты'
          end

        matched_year = item['_year'].to_s
        link_full = ArshinService.registry_link_for_serial(details[:serial], year: matched_year.empty? ? nil : matched_year)
        link = ArshinService.shorten_url(link_full)

        lines = [
          "🔎 Данные АРШИН#{matched_year.empty? ? '' : " (запись за #{matched_year} г.)"}:",
          "  Поверитель: #{arshin_org.empty? ? '—' : arshin_org}",
          "  Дата поверки: #{arshin_verif.empty? ? '—' : arshin_verif}",
          "  Действительна до: #{arshin_valid.empty? ? '—' : arshin_valid}",
          "  Документ: #{arshin_doc.empty? ? '—' : arshin_doc}",
          "  Пригодность: #{arshin_applicable}",
          '',
          "В таблице: #{table_next.empty? ? '—' : table_next}",
          cmp_line,
          '',
          "Проверить вручную: #{link}"
        ]
        has_vri = !vri_id.empty?
        send_to_max_chat(lines.join("\n"), chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial, has_arshin_snap: has_vri))
      end
      return
    when /\Abilling:put_arshin_snap\z/i
      arshin_item = state[:arshin_item]
      if arshin_item.nil? || arshin_item[:vri_id].to_s.strip.empty?
        send_to_max_chat('Сначала нажмите «Проверить в АРШИН».', chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
        return
      end
      start_arshin_snapshot_flow(chat_id, arshin_item, back_keyboard: max_billing_card_keyboard(has_serial: has_serial, has_arshin_snap: true))
      return
    when /\Abilling:back_card\z/i
      send_to_max_chat(billing_format_card(state[:details]), chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
      return
    when /\Abilling:back_results\z/i
      matches = state[:matches] || []
      page = state[:page].to_i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_results', matches: matches, page: page } }
      send_to_max_chat('Выберите:', chat_id, attachments: max_billing_results_keyboard(matches, page: page))
      return
    when /\Abilling:menu\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = { mode: 'billing_menu' } }
      send_to_max_chat(billing_menu_greeting, chat_id, attachments: max_billing_menu_keyboard(user_id))
      return
    end
    send_to_max_chat('Выберите кнопкой.', chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
    return
  end

  if state && state[:mode] == 'billing_input_value'
    case text
    when /\Abilling:back_card\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_card') }
      send_to_max_chat(billing_format_card(state[:details]), chat_id, attachments: max_billing_card_keyboard(has_serial: !state.dig(:details, :serial).to_s.strip.empty?))
      return
    end

    normalized = text.to_s.strip.tr(',', '.').gsub(/\s+/, '')
    unless normalized.match?(/\A\d+(\.\d+)?\z/)
      send_to_max_chat('Нужно число (например 123 или 123,45). Попробуй снова:', chat_id, attachments: max_billing_cancel_keyboard)
      return
    end

    value_for_write = text.to_s.strip
    MAX_STATES_MUTEX.synchronize do
      MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_input_date', pending_value: value_for_write)
    end
    today = BillingService.format_date_ru(BillingService.local_today)
    send_to_max_chat("Введите дату передачи (ДД.ММ.ГГГГ) или жмите «Сегодня» (#{today}):", chat_id, attachments: max_billing_date_keyboard)
    return
  end

  if state && state[:mode] == 'billing_input_date'
    case text
    when /\Abilling:back_card\z/i
      MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_card') }
      has_serial = !state.dig(:details, :serial).to_s.strip.empty?
      send_to_max_chat(billing_format_card(state[:details]), chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
      return
    when /\Abilling:date:today\z/i
      date = BillingService.local_today
    else
      date = BillingService.parse_date_input(text)
    end

    unless date
      send_to_max_chat('Не понял дату. Формат ДД.ММ.ГГГГ, либо «сегодня», либо кнопка:', chat_id, attachments: max_billing_date_keyboard)
      return
    end

    row = state[:row]
    value = state[:pending_value]
    ok, err = BillingService.write_readings(row, value, BillingService.format_date_ru(date))
    has_serial = !state.dig(:details, :serial).to_s.strip.empty?
    unless ok
      send_to_max_chat("❌ Ошибка записи: #{err}", chat_id, attachments: max_billing_card_keyboard(has_serial: has_serial))
      return
    end

    refreshed = BillingService.object_details(row) || state[:details]
    MAX_STATES_MUTEX.synchronize do
      MAX_USER_STATES[chat_id] = state.merge(mode: 'billing_card', details: refreshed).tap { |s| s.delete(:pending_value) }
    end
    send_to_max_chat("✅ Записано: #{value} на #{BillingService.format_date_ru(date)}", chat_id)
    send_to_max_chat(billing_format_card(refreshed), chat_id, attachments: max_billing_card_keyboard(has_serial: !refreshed[:serial].to_s.strip.empty?))
    return
  end

  max_send_main_menu(chat_id)
end

def sheets_daily_push
  return unless SheetsService.enabled?

  SheetsService.refresh(force: true)
  date = Time.now.getlocal('+07:00').to_date
  dates = SheetsService.available_dates
  unless dates.include?(date)
    max_log("daily_push skipped: today #{date} not in schedule dates=#{dates.inspect}")
    return
  end

  sent = 0
  skipped = 0
  UserProfiles.each_user do |user_id, profile|
    name = profile['name']
    cid = profile['chat_id']
    next if name.to_s.empty? || cid.nil? || cid.to_i.zero?

    tasks = SheetsService.tasks_for(name, date)
    if tasks.empty?
      skipped += 1
      next
    end

    body = tasks.map { |t| "🕗 #{t[:time]}\n    #{t[:task]}" }.join("\n\n")
    send_to_max_chat("Задания на день\n\n#{body}", cid.to_i)
    sent += 1
  rescue => e
    max_log("daily_push error for user=#{user_id}: #{e.class}: #{e.message}")
  end
  max_log("daily_push completed: sent=#{sent} skipped=#{skipped}")
end

def sheets_diff_report(old_tasks, new_tasks)
  old_map = (old_tasks || []).each_with_object({}) { |t, h| h[t['time'].to_s] = t['task'].to_s }
  new_map = (new_tasks || []).each_with_object({}) { |t, h| h[t[:time].to_s] = t[:task].to_s }

  added = new_map.keys - old_map.keys
  removed = old_map.keys - new_map.keys
  changed = (old_map.keys & new_map.keys).select { |k| old_map[k] != new_map[k] }

  return nil if added.empty? && removed.empty? && changed.empty?

  lines = ['🔔 Изменения в расписании на сегодня:', '']
  added.each do |t|
    lines << "➕ #{t}"
    lines << "    #{new_map[t]}"
  end
  changed.each do |t|
    lines << "✏ #{t}"
    lines << "    было: #{old_map[t]}"
    lines << "    стало: #{new_map[t]}"
  end
  removed.each do |t|
    lines << "➖ #{t} — удалено"
    lines << "    было: #{old_map[t]}"
  end
  lines.join("\n")
end

def sheets_seed_snapshots(user_id, name, dates = nil)
  return nil

  dates ||= begin
    today = Date.today
    available = SheetsService.available_dates
    [today, today + 1].select { |d| available.include?(d) }
  end

  dates.each do |_date|
    # legacy stub
  end
end

def sheets_check_changes
  return nil

  return unless SheetsService.enabled?
  return unless SheetsService.work_hour?

  today = Date.today
  tomorrow = today + 1
  dates = SheetsService.available_dates
  targets = [today, tomorrow].select { |d| dates.include?(d) }
  return if targets.empty?

  sent = 0
  UserProfiles.each_user do |user_id, profile|
    name = profile['name']
    cid = profile['chat_id']
    next if name.to_s.empty? || cid.nil? || cid.to_i.zero?

    targets.each do |date|
      old_tasks = nil
      new_tasks = SheetsService.tasks_for(name, date)

      if old_tasks.nil?
        next
      end

      report = sheets_diff_report(old_tasks, new_tasks)
      next unless report

      day_label = date == today ? 'на сегодня' : "на #{date.strftime('%d.%m')}"
      send_to_max_chat(report.sub('на сегодня', day_label), cid.to_i)
      sent += 1
    end
  rescue => e
    max_log("sheets_check_changes error for user=#{user_id}: #{e.class}: #{e.message}")
  end
  max_log("sheets_check_changes: notifications_sent=#{sent}") if sent > 0
end

def notify_journal_events_once
  return unless JournalService.enabled?

  sent = JournalNotifyService.process_pending_events(deliver: method(:send_to_max_chat))
  max_log("notify_journal_events: sent=#{sent}") if sent.positive?
rescue StandardError => e
  max_log("notify_journal_events_once error: #{e.class}: #{e.message}")
end

def start_journal_events_scheduler
  return unless JournalService.enabled?

  @journal_events_scheduler ||= Rufus::Scheduler.new
  @journal_events_scheduler.every '15s' do
    notify_journal_events_once
  end
  max_log('Journal events scheduler started (every 15s)')
rescue StandardError => e
  max_log("start_journal_events_scheduler error: #{e.class}: #{e.message}")
end

def billing_resolve_chat_id(user_id)
  chat = UserProfiles.chat_id_for(user_id)
  return chat.to_i if chat && chat.to_i > 0

  rec = MaxUsersLog.all[user_id.to_s]
  cid = rec && rec['chat_id']
  cid ? cid.to_i : nil
end

def billing_can_create_month_in_bot?(user_id)
  allowed_logins = BillingService.month_creator_logins
  if allowed_logins.any?
    bindings = MaxNotifyService.site_user_max_bindings # login => max_user_id
    matched_login = bindings.find { |_login, max_uid| max_uid.to_s == user_id.to_s }&.first
    return false if matched_login.to_s.strip.empty?
    return BillingService.user_can_create_month_login?(matched_login)
  end

  BillingService.user_can_create_month?(user_id)
rescue => e
  max_log("billing_can_create_month_in_bot error: #{e.class}: #{e.message}")
  false
end

def billing_month_creator_user_ids
  allowed_logins = BillingService.month_creator_logins
  if allowed_logins.any?
    bindings = MaxNotifyService.site_user_max_bindings # login => max_user_id
    return allowed_logins.filter_map { |login| bindings[login].to_s.strip }.reject(&:empty?).uniq
  end
  BillingService.month_creator_ids
rescue => e
  max_log("billing_month_creator_user_ids error: #{e.class}: #{e.message}")
  BillingService.month_creator_ids
end

def billing_new_month_reminder_push
  return unless BillingService.enabled?

  ids = billing_month_creator_user_ids
  return if ids.empty?

  current = BillingService.current_sheet
  next_name = current ? BillingService.next_month_name(current[:name]) : nil
  text = +"📅 Напоминание\n\nНачался новый месяц — пора создать следующую вкладку в ГВС биллинге."
  text << "\nТекущая вкладка: «#{current[:name]}»." if current
  text << "\nСоздать вкладку: «#{next_name}»." if next_name
  text << "\n\nЗайди в «Электронные журналы → ГВС биллинг → 📅 Создать следующий месяц»."

  ids.each do |uid|
    cid = billing_resolve_chat_id(uid)
    next unless cid

    begin
      send_to_max_chat(text, cid)
    rescue => e
      max_log("billing_new_month_reminder error for user=#{uid}: #{e.class}: #{e.message}")
    end
  end
  max_log("billing_new_month_reminder sent to #{ids.size} users")
end

def start_billing_monthly_reminder
  cron = ENV['BILLING_NEW_MONTH_REMINDER_CRON'] || '0 9 1 * *'
  @billing_reminder_scheduler ||= Rufus::Scheduler.new
  @billing_reminder_scheduler.cron(cron) do
    billing_new_month_reminder_push
  end
  max_log("Billing monthly reminder scheduler started (cron: #{cron})")
rescue => e
  max_log("start_billing_monthly_reminder error: #{e.class}: #{e.message}")
end

def billing_send_expiring_poverki(chat_id, until_date: nil)
  return unless BillingService.enabled?

  items =
    if until_date
      BillingService.expiring_poverki(until_date: until_date)
    else
      within = (ENV['BILLING_POVERKI_HORIZON_DAYS'] || '30').to_i
      BillingService.expiring_poverki(within_days: within)
    end

  horizon_label =
    if until_date
      "до #{BillingService.format_date_ru(until_date)}"
    else
      "ближайшие #{(ENV['BILLING_POVERKI_HORIZON_DAYS'] || '30').to_i} дней"
    end

  if items.empty?
    send_to_max_chat("✅ Истекающих поверок #{horizon_label} нет.", chat_id)
    return
  end

  lines = ["⚠ Истекающие поверки (#{horizon_label}): #{items.size}", '']
  items.first(50).each_with_index do |it, idx|
    lines << "#{idx + 1}. #{it[:name]} — #{it[:address]}"
    lines << "   Поверка до: #{it[:poverka_next]} (через #{it[:days_left]} дн.)"
    lines << "   Заводской №: #{it[:serial]}" unless it[:serial].to_s.strip.empty?
    lines << ''
  end
  lines << '(показаны первые 50)' if items.size > 50
  send_to_max_chat(lines.join("\n"), chat_id)
rescue => e
  max_log("billing_send_expiring_poverki error: #{e.class}: #{e.message}")
end

def start_sheets_daily_scheduler
  @sheets_scheduler ||= Rufus::Scheduler.new(timezone: 'Asia/Tomsk')
  @last_sheets_daily_push_date ||= nil
  @sheets_scheduler.cron('* * * * *') do
    now = Time.now.getlocal('+07:00')
    configured = AppSettings.get('daily_tasks_notify_time').to_s.strip
    configured = '08:00' unless configured.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)
    current_hhmm = now.strftime('%H:%M')
    today = now.to_date
    next unless current_hhmm == configured
    next if @last_sheets_daily_push_date == today

    sheets_daily_push
    @last_sheets_daily_push_date = today
  end
  max_log('SheetsService daily scheduler started (dynamic daily time, check every minute, tz: Asia/Tomsk)')
rescue => e
  max_log("start_sheets_daily_scheduler error: #{e.class}: #{e.message}")
end

def start_contacts_sync_scheduler
  return unless ContactsSyncService.enabled?

  cron = (ENV['CONTACTS_SYNC_CRON'] || '15 8 * * 1-5').to_s
  @contacts_scheduler ||= Rufus::Scheduler.new
  @contacts_scheduler.cron(cron) do
    begin
      ok, summary = ContactsSyncService.sync(force: true)
      if ok
        total = summary.is_a?(Hash) ? summary.values.sum { |v| v[:count].to_i } : 0
        max_log("ContactsSyncService scheduled sync ok: total=#{total}")
      else
        max_log("ContactsSyncService scheduled sync failed: #{summary}")
      end
    rescue => e
      max_log("ContactsSyncService scheduled sync error: #{e.class}: #{e.message}")
    end
  end
  max_log("ContactsSyncService scheduler started (cron: #{cron})")
rescue => e
  max_log("start_contacts_sync_scheduler error: #{e.class}: #{e.message}")
end

def daily_db_backup_job
  result = DbBackupService.create_backup
  if result[:ok]
    max_log("db_backup completed: #{result[:zip]}")
    MaxNotifyService.notify_db_backup_event("✅ Ежедневный бэкап БД выполнен\nФайл: #{File.basename(result[:zip])}\nВремя: #{Time.now.getlocal('+07:00').strftime('%d.%m.%Y %H:%M:%S')}")
  else
    max_log("db_backup failed: #{result[:error]}")
    MaxNotifyService.notify_db_backup_event("❌ Ежедневный бэкап БД не выполнен\nОшибка: #{result[:error]}")
  end

  mail_result = DbBackupService.send_email_report(result)
  unless mail_result[:ok]
    max_log("db_backup mail skipped/failed: #{mail_result[:error]}")
  end
rescue => e
  max_log("daily_db_backup_job error: #{e.class}: #{e.message}")
  MaxNotifyService.notify_db_backup_event("❌ Ежедневный бэкап БД: ошибка #{e.class}")
end

def start_db_backup_scheduler
  @db_backup_scheduler ||= Rufus::Scheduler.new(timezone: 'Asia/Tomsk')
  @last_db_backup_date ||= nil
  @db_backup_scheduler.cron('* * * * *') do
    next unless DbBackupService.enabled?

    now = Time.now.getlocal('+07:00')
    current_hhmm = now.strftime('%H:%M')
    next unless current_hhmm == DbBackupService.daily_time

    today = now.to_date
    next if @last_db_backup_date == today

    daily_db_backup_job
    @last_db_backup_date = today
  end
  max_log('DB backup scheduler started (dynamic daily time, check every minute, tz: Asia/Tomsk)')
rescue => e
  max_log("start_db_backup_scheduler error: #{e.class}: #{e.message}")
end

def daily_water_uute_refresh_job
  result = WaterRegistryService.refresh_water_uute_links!
  max_log("water_uute_refresh completed: updated=#{result[:updated]}")
rescue => e
  max_log("daily_water_uute_refresh_job error: #{e.class}: #{e.message}")
end

def start_water_uute_refresh_scheduler
  @water_uute_scheduler ||= Rufus::Scheduler.new(timezone: 'Asia/Tomsk')
  @last_water_uute_refresh_date ||= nil
  @water_uute_scheduler.cron('* * * * *') do
    now = Time.now.getlocal('+07:00')
    next unless now.strftime('%H:%M') == '07:00'

    today = now.to_date
    next if @last_water_uute_refresh_date == today

    daily_water_uute_refresh_job
    @last_water_uute_refresh_date = today
  end
  max_log('Water UUTE refresh scheduler started (daily at 07:00, tz: Asia/Tomsk)')
rescue => e
  max_log("start_water_uute_refresh_scheduler error: #{e.class}: #{e.message}")
end

def start_max_long_polling
  return unless MAX_ENABLED && MAX_INBOUND_ENABLED
  return if MAX_BOT_TOKEN.empty?

  Thread.new do
    marker = nil
    max_log("MAX long polling started (inbound=#{MAX_INBOUND_ENABLED}, webhook=#{MAX_WEBHOOK_ENABLED})")
    loop do
      begin
        uri = URI('https://platform-api.max.ru/updates')
        params = { limit: 100 }
        params[:marker] = marker unless marker.nil?
        uri.query = URI.encode_www_form(params)

        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = MAX_BOT_TOKEN

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        res = http.request(req)
        body_str = res.body.to_s

        if res.is_a?(Net::HTTPSuccess) && !body_str.strip.empty?
          data = JSON.parse(body_str) rescue {}
          marker = data['marker'] if data.is_a?(Hash)
          updates = data.is_a?(Hash) ? data['updates'] : []
          updates = [] unless updates.is_a?(Array)

          updates.each do |upd|
            next if max_handle_dialog_open_update(upd)

            chat_id = upd.dig('message', 'recipient', 'chat_id') ||
              upd['chat_id'] ||
              upd.dig('message', 'chat', 'id') ||
              upd['peer_id']
            next if chat_id.nil? || chat_id.to_s.empty?

            max_log_identity(upd, chat_id)
            user_id_from_upd = max_user_id_from_update(upd)
            unless max_user_allowed?(user_id_from_upd)
              max_reject_unauthorized(chat_id, user_id_from_upd)
              next
            end

            attachments_in = upd.dig('message', 'body', 'attachments')
            uploadable_types = %w[image file video]
            has_uploadable = attachments_in.is_a?(Array) && attachments_in.any? { |a| uploadable_types.include?(a['type'].to_s) }

            if has_uploadable
              state_for_photo = MAX_STATES_MUTEX.synchronize { MAX_USER_STATES[chat_id.to_i] }
              if state_for_photo && state_for_photo[:mode] == 'yadisk_upload'
                folder = state_for_photo[:folder]
                count = state_for_photo[:count].to_i
                ok_count = 0
                err_count = 0
                last_error = nil

                attachments_in.each do |att|
                  att_type = att['type'].to_s
                  next unless uploadable_types.include?(att_type)

                  url = att.dig('payload', 'url')
                  next if url.to_s.empty?

                  ts = Time.now.strftime('%Y%m%d_%H%M%S')

                  filename =
                    if att_type == 'file'
                      orig_name = att.dig('payload', 'filename').to_s.strip
                      orig_name = att.dig('payload', 'name').to_s.strip if orig_name.empty?
                      orig_name.empty? ? "file_#{ts}_#{rand(10000)}" : "#{ts}_#{orig_name}"
                    elsif att_type == 'video'
                      vid_id = att.dig('payload', 'video_id') || att.dig('payload', 'id')
                      suffix = vid_id.to_s.empty? ? rand(10000).to_s : vid_id.to_s
                      "video_#{ts}_#{suffix}.mp4"
                    else
                      photo_id = att.dig('payload', 'photo_id')
                      suffix = photo_id.to_s.empty? ? rand(10000).to_s : photo_id.to_s
                      "photo_#{ts}_#{suffix}.jpg"
                    end

                  ok, _dest, err = YadiskService.upload_from_url(folder, filename, url)
                  if ok
                    ok_count += 1
                  else
                    err_count += 1
                    last_error = err
                  end
                end

                count += ok_count
                MAX_STATES_MUTEX.synchronize do
                  cur = MAX_USER_STATES[chat_id.to_i]
                  if cur && cur[:mode] == 'yadisk_upload' && cur[:folder] == folder
                    MAX_USER_STATES[chat_id.to_i] = cur.merge(count: count)
                  end
                end

                next_info = sheets_next_task_with_address(state_for_photo[:sheets_context])
                if err_count.zero?
                  send_to_max_chat("✅ Загружено: +#{ok_count} (всего #{count}) в папку «#{YadiskService.folder_display_name(folder)}».", chat_id, attachments: max_yadisk_upload_keyboard(next_info))
                else
                  send_to_max_chat("Загружено: +#{ok_count}, ошибок: #{err_count}. Последняя: #{last_error}", chat_id, attachments: max_yadisk_upload_keyboard(next_info))
                end
                next
              else
                max_log("MAX attachment received chat_id=#{chat_id} without upload state")
              end
            end

            MaxUsersLog.record(upd, chat_id: chat_id)

            callback_id = upd.dig('callback', 'callback_id')
            callback_payload = upd.dig('callback', 'payload')
            if callback_id && !callback_id.to_s.empty?
              message_key = max_message_key(upd, chat_id.to_i)
              max_answer_callback(callback_id)
              process_max_update(chat_id.to_i, callback_payload.to_s, message_key, user_id: user_id_from_upd)
              next
            end

            text = upd.dig('message', 'body', 'text') || upd.dig('message', 'text') || upd['text']
            text_str = text.is_a?(String) ? text.strip : ''
            empty_text = text.nil? || !text.is_a?(String) || text_str.empty?

            if empty_text
              if upd['update_type'].to_s == 'message_created' && !has_uploadable
                max_welcome_after_start(upd, chat_id)
              end
              next
            end

            process_max_update(chat_id.to_i, text_str, max_message_key(upd, chat_id.to_i), user_id: user_id_from_upd)
          end
        elsif MAX_DEBUG
          max_log("MAX /updates failed code=#{res.code} body=#{body_str[0, 300].inspect}")
        end
      rescue => e
        max_log("MAX /updates error: #{e.class}: #{e.message}")
      ensure
        sleep MAX_POLL_INTERVAL
      end
    end
  end
end

def parse_http_request(socket)
  request_line = socket.gets
  return nil if request_line.nil?

  method, path, _http_version = request_line.split(' ')
  headers = {}
  while (line = socket.gets)
    line = line.strip
    break if line.empty?

    key, value = line.split(':', 2)
    headers[key.to_s.downcase] = value.to_s.strip
  end

  content_length = headers['content-length'].to_i
  body = content_length.positive? ? socket.read(content_length).to_s : ''

  { method: method.to_s, path: path.to_s, headers: headers, body: body }
end

def write_http_response(socket, status_code, body_text)
  status_message = status_code == 200 ? 'OK' : 'Not Found'
  body = body_text.to_s
  socket.write("HTTP/1.1 #{status_code} #{status_message}\r\n")
  socket.write("Content-Type: text/plain; charset=utf-8\r\n")
  socket.write("Content-Length: #{body.bytesize}\r\n")
  socket.write("Connection: close\r\n\r\n")
  socket.write(body)
end

def start_max_webhook_server
  return unless MAX_ENABLED && MAX_WEBHOOK_ENABLED
  return if MAX_BOT_TOKEN.empty?

  Thread.new do
    server = TCPServer.new('127.0.0.1', MAX_WEBHOOK_PORT)
    max_log("MAX webhook started on 127.0.0.1:#{MAX_WEBHOOK_PORT} path=#{MAX_WEBHOOK_PATH}")

    loop do
      socket = server.accept
      Thread.new(socket) do |client|
        begin
          req = parse_http_request(client)
          if req && req[:method] == 'POST' && req[:path] == MAX_WEBHOOK_PATH
            upd = JSON.parse(req[:body]) rescue {}
            processed = false

            unless max_handle_dialog_open_update(upd)
              chat_id = upd.dig('message', 'recipient', 'chat_id') ||
                upd['chat_id'] ||
                upd.dig('message', 'chat', 'id') ||
                upd['peer_id']

              if chat_id && !chat_id.to_s.empty?
                max_log_identity(upd, chat_id, 'webhook')
                callback_id = upd.dig('callback', 'callback_id')
                callback_payload = upd.dig('callback', 'payload')

                uid = max_user_id_from_update(upd)
                unless max_user_allowed?(uid)
                  max_reject_unauthorized(chat_id, uid)
                  write_http_response(client, 200, 'forbidden')
                  next
                end

                MaxUsersLog.record(upd, chat_id: chat_id)

                if callback_id && !callback_id.to_s.empty?
                  max_answer_callback(callback_id)
                  process_max_update(chat_id.to_i, callback_payload.to_s, max_message_key(upd, chat_id.to_i), user_id: uid)
                  processed = true
                else
                  text = upd.dig('message', 'body', 'text') || upd.dig('message', 'text') || upd['text']
                  if text.is_a?(String) && !text.strip.empty?
                    process_max_update(chat_id.to_i, text.to_s.strip, max_message_key(upd, chat_id.to_i), user_id: uid)
                    processed = true
                  end
                end
              end
            else
              processed = true
            end

            write_http_response(client, 200, processed ? 'ok' : 'ignored')
          else
            write_http_response(client, 404, 'not found')
          end
        rescue => e
          max_log("MAX webhook error: #{e.class}: #{e.message}")
          write_http_response(client, 200, 'error') rescue nil
        ensure
          client.close rescue nil
        end
      end
    end
  end
end

def start_bot
  unless MAX_ENABLED
    puts 'MAX_ENABLED=0. Бот не запущен.'
    return
  end

  if MAX_BOT_TOKEN.empty?
    puts 'MAX_BOT_TOKEN не задан. Укажите токен в .env.'
    return
  end

  ArshinService.log("ARSHIN debug enabled. log_path=#{ArshinService.log_path}") if ArshinService.debug?

  if YadiskService.enabled?
    Thread.new do
      begin
        t0 = Time.now
        count = YadiskService.all_folders.size
        max_log("YadiskService cache warmed: #{count} folders in #{(Time.now - t0).round(1)}s")
      rescue => e
        max_log("YadiskService warmup error: #{e.class}: #{e.message}")
      end
    end
  end

  if ContactsSyncService.enabled?
    Thread.new do
      begin
        counts = ContactsService.counts
        if counts.values.sum.zero?
          t0 = Time.now
          ok, summary = ContactsSyncService.sync(force: true)
          if ok
            total = summary.is_a?(Hash) ? summary.values.sum { |v| v[:count].to_i } : 0
            max_log("ContactsSyncService initial sync: total=#{total} in #{(Time.now - t0).round(1)}s")
          else
            max_log("ContactsSyncService initial sync failed: #{summary}")
          end
        else
          max_log("ContactsSyncService DB already populated: counts=#{counts.inspect}")
        end
      rescue => e
        max_log("ContactsSyncService initial sync error: #{e.class}: #{e.message}")
      end
    end
  end

  if SheetsService.enabled?
    Thread.new do
      begin
        t0 = Time.now
        SheetsService.refresh(force: true)
        max_log("SheetsService initial load: tab=#{SheetsService.sheet_name.inspect} in #{(Time.now - t0).round(1)}s")
      rescue => e
        max_log("SheetsService initial load error: #{e.class}: #{e.message}")
      end

      loop do
        sleep SheetsService.refresh_interval_minutes * 60
        begin
          SheetsService.refresh(force: true)
          max_log("SheetsService refreshed: tab=#{SheetsService.sheet_name.inspect}")
          # Изменения журнала отправляем событием (почти мгновенно) через journal_events.
        rescue => e
          max_log("SheetsService refresh error: #{e.class}: #{e.message}")
        end
      end
    end
  end

  start_sheets_daily_scheduler if SheetsService.enabled?
  start_journal_events_scheduler if JournalService.enabled?
  start_billing_monthly_reminder if BillingService.enabled?
  start_contacts_sync_scheduler if ContactsSyncService.enabled?
  start_db_backup_scheduler
  start_water_uute_refresh_scheduler
  VerificationPdfService.cleanup_stale

  start_max_long_polling
  start_max_webhook_server

  puts 'MAX бот запущен: активен только сценарий "Поверка приборов в АРШИН".'

  loop { sleep 3600 }
end

begin
  start_bot
rescue Interrupt
  puts "\nБот остановлен"
end
