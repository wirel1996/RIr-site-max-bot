# frozen_string_literal: true

# JSON API ??? React-????????? (web-frontend/).
# ??????: ruby web/app.rb (????? nssm-?????? MaxBotWeb).

require 'sinatra/base'
require 'json'
require 'date'

require 'dotenv/load' if File.exist?(File.expand_path('../.env', __dir__))

require_relative '../services/contacts_service'
require_relative '../services/journal_service'
require_relative '../services/algorithms_service'
require_relative '../services/devices_info_service'
require_relative '../services/sheets_service'
require_relative '../services/arshin_service'
require_relative '../services/billing_service'
require_relative '../services/volume_calc_service'
require_relative '../services/verification_pdf_service'
require_relative '../services/arshin_pdf_helpers'
require_relative '../services/users_service'
require_relative '../services/password_reset_mailer'
require_relative '../services/short_link_service'
require_relative '../services/uute_service'
require_relative '../services/uute_act_service'
require_relative '../services/water_registry_service'
require_relative '../services/water_phoneogram_service'
require_relative '../services/max_notify_service'
require_relative '../services/journal_notify_service'
require_relative '../services/audit_log_service'
require_relative '../services/db_backup_service'
require_relative '../storage/user_profiles'
require_relative '../storage/app_settings'
require_relative '../storage/journal_db'

class ContactsWeb < Sinatra::Base
  FORGOT_PASSWORD_COOLDOWN_SECONDS = 120
  FORGOT_PASSWORD_MUTEX = Mutex.new
  FORGOT_PASSWORD_LAST_REQUEST = {}

  set :root, File.expand_path(__dir__)
  set :public_folder, nil
  set :show_exceptions, :after_handler
  set :bind,        ENV['CONTACTS_WEB_BIND'] || '127.0.0.1'
  set :port,        (ENV['CONTACTS_WEB_PORT'] || '4567').to_i
  set :environment, (ENV['CONTACTS_WEB_ENV'] || 'production').to_sym

  # Cookie-?????? (????????? ????????, persists ????? ?????????????).
  use Rack::Session::Cookie,
      key: 'oke_session',
      secret: UsersService.session_secret,
      expire_after: 30 * 86_400, # 30 ????
      same_site: :lax,
      httponly: true

  # ??????? ??????? ???? ???????, ????? ?????? ?????? /api/journal/weeks ??? ??????????.
  Thread.new do
    sleep 2
    begin
      JournalService.index_all if JournalService.enabled?
    rescue StandardError => e
      warn "JournalService warmup error: #{e.class}: #{e.message}"
    end
  end

  helpers do
    def json_response(data, status_code = 200)
      content_type 'application/json; charset=utf-8'
      status status_code
      JSON.generate(data)
    end

    def json_error(message, status_code = 400)
      json_response({ error: message }, status_code)
    end

    def parse_json_body
      body = request.body.read.to_s
      return {} if body.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      halt 400, json_error('invalid JSON in body', 400)
    end

    def current_user
      login = session[:user_login]
      return nil if login.to_s.empty?
      ver = session[:session_version]
      return nil unless UsersService.session_valid?(login, ver)

      UsersService.find(login)
    end

    def require_auth!
      halt 401, json_error('not authenticated', 401) unless current_user
    end

    def require_admin!
      require_auth!
      halt 403, json_error('admin required', 403) unless UsersService.admin?(current_user)
    end

    def require_billing_access!
      require_auth!
      halt 403, json_error('billing access denied', 403) unless UsersService.billing_allowed?(current_user)
    end

    def require_not_water_payment_only!
      require_auth!
      halt 403, json_error('access denied', 403) if UsersService.water_payment_only?(current_user)
    end

    def water_payment_api_allowed_path?
      path = request.path
      return true if %w[/api/auth/me /api/auth/logout].include?(path)
      return true if request.get? && path == '/api/metering/water'
      return true if request.get? && path.match?(%r{\A/api/metering/water/\d+\z})
      return true if request.patch? && path.match?(%r{\A/api/metering/water/\d+\z})
      return true if request.get? && path == '/api/metering/water/disconnected-export'

      false
    end

    def water_payment_notification(user, record)
      [
        'Оплата по летней воде отмечена как Да.',
        "Пользователь: #{user[:name].to_s.empty? ? user[:login] : user[:name]}",
        "ГСПО: #{record[:gspo_name].to_s.empty? ? '?' : record[:gspo_name]}",
        "Адрес: #{record[:standalone_address].to_s.empty? ? '?' : record[:standalone_address]}",
        "Фактическая точка: #{record[:actual_connection_point].to_s.empty? ? record[:point_number] : record[:actual_connection_point]}",
        "Время: #{Time.now.strftime('%d.%m.%Y %H:%M:%S')}"
      ].join("\n")
    end

    def request_ip
      forwarded = request.env['HTTP_X_FORWARDED_FOR'].to_s.split(',').first.to_s.strip
      forwarded.empty? ? request.ip : forwarded
    end

    def forgot_password_rate_limited?(login_or_email)
      key = "#{request_ip}|#{login_or_email.to_s.strip.downcase}"
      now = Time.now.to_i
      limited = false
      FORGOT_PASSWORD_MUTEX.synchronize do
        last = FORGOT_PASSWORD_LAST_REQUEST[key].to_i
        limited = (now - last) < FORGOT_PASSWORD_COOLDOWN_SECONDS
        FORGOT_PASSWORD_LAST_REQUEST[key] = now unless limited
      end
      limited
    end

    def audit!(action:, entity_type: nil, entity_id: nil, entity_label: nil, field: nil, old_value: nil, new_value: nil, details: nil, actor: nil)
      AuditLogService.record(
        actor: actor || current_user,
        action: action,
        entity_type: entity_type,
        entity_id: entity_id,
        entity_label: entity_label,
        field: field,
        old_value: old_value,
        new_value: new_value,
        details: details,
        ip: request_ip,
        user_agent: request.user_agent
      )
    end

    def contact_label(record)
      [record && (record['name'] || record[:name]), record && (record['address'] || record[:address])].map(&:to_s).reject(&:empty?).join(' - ')
    end

    def water_label(record)
      [record && (record[:gspo_name] || record['gspo_name']), record && (record[:standalone_address] || record['standalone_address'])].map(&:to_s).reject(&:empty?).join(' - ')
    end

    def billing_label(record)
      return '' unless record
      name = (record[:contract_name] || record['contract_name'] || record[:name] || record['name']).to_s
      addr = (record[:address] || record['address']).to_s
      [name, addr].reject(&:empty?).join(' - ')
    end

    def arshin_meter_label(serial_key)
      {
        'calculator_serial' => 'Тепловычислитель',
        'flowmeter_serial_1' => 'Расходомер 1',
        'flowmeter_serial_2' => 'Расходомер 2',
        'temp_sensor_serial_1' => 'Датчик температуры 1',
        'temp_sensor_serial_2' => 'Датчик температуры 2',
        'pressure_sensor_serial_1' => 'Датчик давления 1',
        'pressure_sensor_serial_2' => 'Датчик давления 2'
      }[serial_key.to_s] || serial_key.to_s
    end

    def arshin_audit_summary(data)
      return 'Поверка по АРШИН не была сохранена' unless data.is_a?(Hash) && !data.empty?

      number = (data['mi_number'] || data[:mi_number] || data['mit_number'] || data[:mit_number]).to_s.strip
      notation = (data['mit_notation'] || data[:mit_notation]).to_s.strip
      verification_date = (data['verification_date'] || data[:verification_date]).to_s.strip
      valid_date = (data['valid_date'] || data[:valid_date]).to_s.strip
      org = (data['org_title'] || data[:org_title]).to_s.strip
      registry_url = (data['registry_url'] || data[:registry_url]).to_s.strip
      yadisk_path = (data['yadisk_path'] || data[:yadisk_path]).to_s.strip

      lines = []
      lines << "Номер: #{number}" unless number.empty?
      lines << "Тип: #{notation}" unless notation.empty?
      lines << "Дата поверки: #{verification_date}" unless verification_date.empty?
      lines << "Действует до: #{valid_date}" unless valid_date.empty?
      lines << "Поверитель: #{org}" unless org.empty?
      lines << "АРШИН: #{registry_url}" unless registry_url.empty?
      lines << "PDF: #{yadisk_path}" unless yadisk_path.empty?
      lines.empty? ? 'Поверка по АРШИН сохранена' : lines.join("\n")
    end

    def arshin_checks_from_record(record)
      checks = record && (record['arshin_checks'] || record[:arshin_checks])
      checks.is_a?(Hash) ? checks : {}
    end

    def arshin_item_audit_data(item, registry_url:, yadisk_path:)
      {
        'mi_number' => item['mi_number'],
        'mit_number' => item['mit_number'],
        'mit_notation' => item['mit_notation'],
        'verification_date' => item['verification_date'],
        'valid_date' => item['valid_date'],
        'org_title' => item['org_title'],
        'registry_url' => registry_url,
        'yadisk_path' => yadisk_path
      }
    end
  end

  # ???????? ????? (??? ??????): ?????? ????? ? health.
  AUTH_FREE_PATHS = %w[/api/auth/login /api/auth/forgot /api/auth/reset-password /api/health].freeze

  before '/api/*' do
    request.body.rewind if request.body.respond_to?(:rewind)
  end

  before '/api/*' do
    next if AUTH_FREE_PATHS.include?(request.path)
    next if request.path.match?(%r{\A/api/reset-link/[^/]+\z})

    require_auth!
    halt 403, json_error('water access only', 403) if UsersService.water_payment_only?(current_user) && !water_payment_api_allowed_path?
  end

  before '/api/billing/*' do
    require_billing_access!
  end

  # ---- Auth ----
  post '/api/auth/login' do
    body = parse_json_body
    login = body['login'].to_s
    password = body['password'].to_s
    halt 400, json_error('Логин и пароль обязательны', 400) if login.empty? || password.empty?

    user = UsersService.authenticate(login, password)
    halt 401, json_error('Неверный логин или пароль', 401) unless user

    session[:user_login] = user[:login]
    session[:session_version] = user[:session_version].to_i
    audit!(action: 'login', entity_type: 'auth', entity_id: user[:login], entity_label: user[:name], actor: user)
    json_response(user: user)
  end

  post '/api/auth/logout' do
    session.clear
    json_response(ok: true)
  end

  get '/api/auth/me' do
    user = current_user
    halt 401, json_error('not authenticated', 401) unless user

    UsersService.mark_activity(user[:login], page: request.path)
    json_response(user: UsersService.public_user(UsersService.find(user[:login]) || user))
  end

  post '/api/auth/ping' do
    require_auth!
    body = parse_json_body
    page = body['page'].to_s
    user = UsersService.mark_activity(current_user[:login], page: page)
    json_response(ok: true, user: user || current_user)
  end

  # ---- Admin users ----
  get '/api/admin/users' do
    require_admin!
    json_response(users: UsersService.list)
  end

  get '/api/admin/audit' do
    require_admin!
    limit = params[:limit].to_i
    limit = AuditLogService::DEFAULT_LIMIT if limit <= 0
    json_response(logs: AuditLogService.list(limit: limit, actor: params[:actor], entity_type: params[:entity_type], exclude_entity_type: 'journal'))
  end

  get '/api/admin/audit/export' do
    require_admin!
    entity_type = params[:entity_type].to_s.strip
    if entity_type.empty?
      path, filename = AuditLogService.export_xls(exclude_entity_type: 'journal')
    else
      path, filename = AuditLogService.export_xls(entity_type: entity_type, filename_prefix: "#{entity_type}_audit")
    end
    send_file path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  end

  get '/api/admin/journal-audit' do
    require_admin!
    limit = params[:limit].to_i
    limit = AuditLogService::DEFAULT_LIMIT if limit <= 0
    json_response(logs: AuditLogService.list(limit: limit, actor: params[:actor], entity_type: 'journal'))
  end

  get '/api/admin/journal-audit/export' do
    require_admin!
    path, filename = AuditLogService.export_journal_xls
    send_file path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  end

  get '/api/admin/metering-audit' do
    require_admin!
    limit = params[:limit].to_i
    limit = AuditLogService::DEFAULT_LIMIT if limit <= 0
    json_response(logs: AuditLogService.list(limit: limit, actor: params[:actor], entity_type: 'metering'))
  end

  get '/api/admin/metering-audit/export' do
    require_admin!
    path, filename = AuditLogService.export_xls(entity_type: 'metering', filename_prefix: 'metering_audit')
    send_file path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  end

  get '/api/admin/max-users' do
    require_admin!
    daily_time = AppSettings.get('daily_tasks_notify_time').to_s.strip
    daily_time = '08:00' unless daily_time.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)
    json_response(
      users: MaxNotifyService.max_users,
      water_payment_notify_user_id: MaxNotifyService.water_payment_notify_user_id,
      water_payment_notify_user_ids: MaxNotifyService.water_payment_notify_user_ids,
      journal_notify_user_ids: MaxNotifyService.journal_notify_user_ids,
      journal_notify_logins: MaxNotifyService.journal_notify_logins,
      site_user_max_bindings: MaxNotifyService.site_user_max_bindings,
      daily_tasks_notify_time: daily_time,
      billing_month_creator_logins: BillingService.month_creator_logins,
      db_backup_enabled: DbBackupService.enabled?,
      db_backup_email: DbBackupService.email_to,
      db_backup_daily_time: DbBackupService.daily_time,
      db_backup_notify_user_id: MaxNotifyService.db_backup_notify_user_id
    )
  end

  patch '/api/auth/profile' do
    require_auth!
    body = parse_json_body
    user = UsersService.update(
      login: current_user[:login],
      name: body.key?('name') ? body['name'].to_s : nil,
      email: body.key?('email') ? body['email'].to_s : nil,
      position: body.key?('position') ? body['position'].to_s : nil,
      password: body.key?('password') ? body['password'].to_s : nil
    )
    session[:user_login] = user[:login]
    session[:session_version] = user[:session_version].to_i
    json_response(user: user)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  post '/api/auth/logout-all' do
    require_auth!
    ok = UsersService.revoke_sessions(current_user[:login])
    halt 400, json_error('unable to revoke sessions', 400) unless ok
    session.clear
    json_response(ok: true)
  end

  post '/api/auth/forgot' do
    body = parse_json_body
    login_or_email = body['login_or_email'].to_s
    if login_or_email.strip.empty?
      halt 400, json_error('login or email required', 400)
    end
    if forgot_password_rate_limited?(login_or_email)
      halt 429, json_error('Запрос на восстановление можно отправлять не чаще одного раза в 2 минуты', 429)
    end

    data = UsersService.request_password_reset(login_or_email)
    if data.nil?
      if login_or_email.include?('@')
        halt 404, json_error('Пользователь с таким email не найден', 404)
      else
        halt 404, json_error('Пользователь с таким логином не найден', 404)
      end
    end

    halt 400, json_error('У пользователя не указан email', 400) if data[:email].to_s.strip.empty?
    halt 503, json_error('Почтовый сервис не настроен', 503) unless PasswordResetMailer.configured?

    if data && !data[:email].to_s.strip.empty? && PasswordResetMailer.configured?
      base = ENV['APP_BASE_URL'].to_s.strip
      base = "#{request.base_url}" if base.empty?
      ShortLinkService.cleanup!
      reset_direct = "#{base}/login?reset_token=#{data[:token]}"
      code = ShortLinkService.create(target: reset_direct, expires_at: data[:expires_at])
      reset_link = "#{base}/api/reset-link/#{code}"
      # Дополнительно прогоняем через внешний shortlink по запросу заказчика.
      # Если сервис недоступен, останется внутренняя короткая ссылка.
      reset_link = ArshinService.shorten_url(reset_link)
      begin
        PasswordResetMailer.send_reset(email: data[:email], login: data[:login], reset_link: reset_link)
      rescue Net::SMTPFatalError => e
        halt 502, json_error("Почтовый сервер отклонил письмо: #{e.message}", 502)
      rescue Net::SMTPAuthenticationError
        halt 502, json_error('Ошибка авторизации SMTP (проверьте логин/пароль приложения)', 502)
      rescue Net::SMTPServerBusy
        halt 503, json_error('Почтовый сервер временно недоступен, попробуйте позже', 503)
      rescue StandardError => e
        halt 502, json_error("Не удалось отправить письмо: #{e.class}", 502)
      end
    end
    json_response(ok: true)
  end

  get '/api/reset-link/:code' do |code|
    target = ShortLinkService.resolve(code)
    halt 404, 'Link not found or expired' if target.to_s.empty?
    redirect target, 302
  end

  post '/api/auth/reset-password' do
    body = parse_json_body
    token = body['token'].to_s
    password = body['password'].to_s
    ok = UsersService.reset_password(token, password)
    halt 400, json_error('invalid or expired token', 400) unless ok
    json_response(ok: true)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/admin/settings/water-payment-notify' do
    require_admin!
    body = parse_json_body
    user_ids = body.key?('user_ids') ? body['user_ids'] : [body['user_id']]
    user_ids = MaxNotifyService.set_water_payment_notify_user_ids(user_ids)
    json_response(
      water_payment_notify_user_id: user_ids.first.to_s,
      water_payment_notify_user_ids: user_ids
    )
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/admin/settings/journal-notify' do
    require_admin!
    body = parse_json_body
    user_ids = body.key?('user_ids') ? body['user_ids'] : [body['user_id']]
    user_ids = MaxNotifyService.set_journal_notify_user_ids(user_ids)
    json_response(journal_notify_user_ids: user_ids)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/admin/settings/journal-notify-logins' do
    require_admin!
    body = parse_json_body
    logins = body['logins']
    logins = MaxNotifyService.set_journal_notify_logins(logins)
    json_response(journal_notify_logins: logins)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/admin/settings/site-user-max-bindings' do
    require_admin!
    body = parse_json_body
    bindings = body['bindings']
    bindings = MaxNotifyService.set_site_user_max_bindings(bindings)
    json_response(site_user_max_bindings: bindings)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/admin/settings/daily-tasks-notify-time' do
    require_admin!
    body = parse_json_body
    raw = body['time'].to_s.strip
    m = raw.match(/\A(\d{1,2}):(\d{1,2})\z/)
    halt 400, json_error('time must be HH:MM', 400) unless m
    hh = m[1].to_i
    mm = m[2].to_i
    halt 400, json_error('time must be HH:MM', 400) unless hh.between?(0, 23) && mm.between?(0, 59)
    time = format('%02d:%02d', hh, mm)
    AppSettings.set('daily_tasks_notify_time', time)
    json_response(daily_tasks_notify_time: time)
  end

  patch '/api/admin/settings/billing-month-creators' do
    require_admin!
    body = parse_json_body
    logins = Array(body['logins']).map { |v| v.to_s.strip.downcase }.reject(&:empty?).uniq
    AppSettings.set('billing_month_creator_logins', logins)
    json_response(billing_month_creator_logins: logins)
  end

  patch '/api/admin/settings/db-backup' do
    require_admin!
    body = parse_json_body
    enabled = body['enabled'] == true
    email = body['email'].to_s.strip
    time = body['time'].to_s.strip
    notify_user_id = body['notify_user_id'].to_s.strip
    if !time.empty? && !time.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)
      halt 400, json_error('time must be HH:MM', 400)
    end
    AppSettings.set('db_backup_enabled', enabled)
    AppSettings.set('db_backup_email', email)
    AppSettings.set('db_backup_daily_time', time.empty? ? DbBackupService.daily_time : time)
    MaxNotifyService.set_db_backup_notify_user_id(notify_user_id)
    json_response(
      db_backup_enabled: AppSettings.get('db_backup_enabled') == true,
      db_backup_email: AppSettings.get('db_backup_email').to_s,
      db_backup_daily_time: AppSettings.get('db_backup_daily_time').to_s,
      db_backup_notify_user_id: MaxNotifyService.db_backup_notify_user_id
    )
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  get '/api/admin/journal-subscriptions' do
    require_admin!
    bindings = AppSettings.get('journal_subscriber_bindings')
    bindings = {} unless bindings.is_a?(Hash)

    normalize_name = JournalNotifyService.method(:normalize_person_name)

    journal_people =
      begin
        weeks = JournalService.weeks
        target = weeks.find { |w| w[:contains_today] } || weeks.last
        week_data = target ? JournalService.read_week(target[:start].to_s) : nil
        grouped = {}
        Array(week_data && week_data[:people]).each do |person|
          key = normalize_name.call(person)
          next if key.empty?
          grouped[key] ||= 0
          grouped[key] += 1
        end
        grouped.keys.sort.map { |name| { name: name, count: grouped[name] } }
      rescue StandardError
        []
      end

    # ????????? ?????? ?????????? ?? ??????? ???????? ? ?????? ????????,
    # ????? ? ?????????? ?? ????????? ????, ? ??????? ?????? ??? ???????
    # ?? ????????? 180 ???? (????????, ??????/?????? ?????????).
    existing = journal_people.each_with_object({}) { |x, h| h[x[:name]] = x[:count].to_i }
    UserProfiles.each_user do |uid, profile|
      n1 = normalize_name.call(profile['name'])
      existing[n1] ||= 0 unless n1.empty?
      n2 = normalize_name.call(bindings[uid.to_s])
      existing[n2] ||= 0 unless n2.empty?
    end
    journal_people = existing.keys.sort.map { |name| { name: name, count: existing[name] } }

    subscribers = []
    UserProfiles.each_user do |uid, profile|
      chat_id = profile['chat_id'].to_i
      next if chat_id <= 0
      subscribers << {
        user_id: uid.to_s,
        subscribed_name: profile['name'].to_s,
        chat_id: chat_id,
        binding: bindings[uid.to_s].to_s
      }
    end

    json_response(journal_people: journal_people, subscribers: subscribers, bindings: bindings)
  end

  patch '/api/admin/journal-subscriptions/:user_id' do |user_id|
    require_admin!
    body = parse_json_body
    journal_name = body['journal_name'].to_s

    data = JournalNotifyService.bind_max_user(user_id, journal_name)
    json_response(ok: true, bindings: data)
  end

  delete '/api/admin/max-users/:user_id/chat-id' do |user_id|
    require_admin!
    deleted = MaxNotifyService.clear_chat_id(user_id)
    halt 404, json_error('MAX ???????????? ?? ??????', 404) unless deleted

    json_response(ok: true)
  end

  post '/api/admin/users' do
    require_admin!
    body = parse_json_body
    login = body['login'].to_s.strip
    name = body['name'].to_s.strip
    password = body['password'].to_s
    role = body['role'].to_s.strip

    halt 400, json_error('login ????????????', 400) if login.empty?
    halt 400, json_error('password ??????? 4 ???????', 400) if password.length < 4
    halt 409, json_error('???????????? ??? ??????????', 409) if UsersService.find(login)

    user = UsersService.upsert(login: login, name: name.empty? ? login : name, password: password, role: role)
    if body.key?('email')
      user = UsersService.update(login: user[:login], email: body['email'].to_s, position: body['position'].to_s)
    elsif body.key?('position')
      user = UsersService.update(login: user[:login], position: body['position'].to_s)
    end
    audit!(
      action: 'admin_user_create',
      entity_type: 'user',
      entity_id: user[:login],
      entity_label: user[:name],
      details: { role: user[:role] }
    )
    json_response({ user: user }, 201)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/admin/users/:login' do |login|
    require_admin!
    body = parse_json_body
    before_user = UsersService.find(login)
    password = body.key?('password') && !body['password'].to_s.empty? ? body['password'].to_s : nil
    changing_current_user = UsersService.normalize(login) == UsersService.normalize(current_user[:login])
    user = UsersService.update(
      login: login,
      new_login: body.key?('login') ? body['login'].to_s : nil,
      name: body.key?('name') ? body['name'].to_s : nil,
      role: body.key?('role') ? body['role'].to_s : nil,
      password: password,
      email: body.key?('email') ? body['email'].to_s : nil,
      position: body.key?('position') ? body['position'].to_s : nil
    )
    session[:user_login] = user[:login] if changing_current_user
    %i[login name role email position].each do |field|
      old_value = before_user && before_user[field]
      new_value = user && user[field]
      next if old_value.to_s == new_value.to_s

      audit!(
        action: 'admin_user_update',
        entity_type: 'user',
        entity_id: user[:login],
        entity_label: user[:name],
        field: field,
        old_value: old_value,
        new_value: new_value
      )
    end
    if password
      audit!(
        action: 'admin_user_password',
        entity_type: 'user',
        entity_id: user[:login],
        entity_label: user[:name],
        field: 'password',
        old_value: 'hidden',
        new_value: 'changed'
      )
    end
    json_response(user: user)
  rescue ArgumentError => e
    status_code = e.message == 'user not found' ? 404 : 400
    halt status_code, json_error(e.message, status_code)
  end

  delete '/api/admin/users/:login' do |login|
    require_admin!
    halt 400, json_error('?????? ??????? ???????? ????????????', 400) if UsersService.normalize(login) == UsersService.normalize(current_user[:login])

    deleted = UsersService.delete(login)
    halt 404, json_error('user not found', 404) unless deleted

    audit!(action: 'admin_user_delete', entity_type: 'user', entity_id: login, entity_label: login)
    json_response(ok: true)
  end

  # ---- Health ----
  get '/api/health' do
    json_response(
      ok: true,
      contacts_db: ContactsService.enabled?,
      time: Time.now.to_i
    )
  end

  # ---- Contacts ----
  get '/api/contacts/overview' do
    counts = ContactsService.counts
    categories = ContactsService.category_records.map do |row|
      cat = row['key'].to_s
      {
        key: cat,
        label: row['label'].to_s,
        sort_order: row['sort_order'].to_i,
        system: row['system'].to_i == 1,
        count: counts[cat].to_i
      }
    end
    json_response(
      categories: categories,
      last_sync_at: ContactsService.last_sync_at
    )
  end

  get '/api/contacts/categories' do
    counts = ContactsService.counts
    categories = ContactsService.category_records.map do |row|
      key = row['key'].to_s
      row.merge(
        'sort_order' => row['sort_order'].to_i,
        'system' => row['system'].to_i == 1,
        'count' => counts[key].to_i
      )
    end
    json_response(categories: categories)
  end

  post '/api/contacts/categories' do
    body = parse_json_body
    category = ContactsService.create_category(body)
    audit!(
      action: 'contact_category_create',
      entity_type: 'contact_category',
      entity_id: category['key'],
      entity_label: category['label']
    )
    json_response(category, 201)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/contacts/categories/:key' do |key|
    before = ContactsService.category_records.find { |row| row['key'].to_s == key.to_s }
    category = ContactsService.update_category(key, parse_json_body)
    halt 404, json_error('not found', 404) unless category
    audit!(
      action: 'contact_category_update',
      entity_type: 'contact_category',
      entity_id: category['key'],
      entity_label: category['label'],
      details: { before: before }
    )
    json_response(category)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  delete '/api/contacts/categories/:key' do |key|
    category = ContactsService.delete_category(key)
    halt 404, json_error('not found', 404) unless category
    audit!(
      action: 'contact_category_delete',
      entity_type: 'contact_category',
      entity_id: category['key'],
      entity_label: category['label']
    )
    json_response(ok: true, category: category)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  get '/api/contacts/search' do
    query = params[:q].to_s.strip
    if query.length < 2
      json_response(query: query, records: [])
    else
      records = ContactsService.search(query)
      json_response(query: query, records: records)
    end
  end

  get '/api/contacts/category/:cat' do |cat|
    halt 404, json_error('unknown category', 404) unless ContactsService.category_exists?(cat)

    page = [params[:page].to_i, 0].max
    query = params[:q].to_s.strip
    records, total = ContactsService.list(cat, page: page, query: query)
    json_response(
      category: cat,
      label: ContactsService.category_label(cat),
      page: page,
      page_size: ContactsService::PAGE_SIZE,
      total: total,
      query: query,
      records: records
    )
  end

  get '/api/contacts/category/:cat/export' do |cat|
    halt 404, json_error('unknown category', 404) unless ContactsService.category_exists?(cat)

    path, filename = ContactsService.export_category(cat)
    send_file path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  end

  post '/api/contacts/category/:cat' do |cat|
    halt 404, json_error('unknown category', 404) unless ContactsService.category_exists?(cat)

    body = parse_json_body
    allowed = %w[name connection_point consumer manager address phone phone_alt email postal_address notes identifier metering_presence disconnected]
    halt 400, json_error('Заполните хотя бы одно поле', 400) if allowed.none? { |key| !body[key].to_s.strip.empty? }

    record = ContactsService.create(cat, body)
    audit!(
      action: 'contact_create',
      entity_type: 'contact',
      entity_id: record['id'],
      entity_label: contact_label(record),
      details: { category: cat }
    )
    json_response(record, 201)
  end

  get '/api/contacts/:id' do |id|
    record = ContactsService.find(id)
    halt 404, json_error('not found', 404) unless record

    json_response(record)
  end

  patch '/api/contacts/:id' do |id|
    before_record = ContactsService.find(id)
    halt 404, json_error('not found', 404) unless before_record

    record = ContactsService.update(id, parse_json_body)
    AuditLogService.record_changes(
      actor: current_user,
      action: 'contact_update',
      entity_type: 'contact',
      entity_id: id,
      entity_label: contact_label(record),
      before: before_record,
      after: record,
      fields: %w[name connection_point consumer manager address phone phone_alt email postal_address notes identifier metering_presence disconnected],
      ip: request_ip,
      user_agent: request.user_agent
    )
    json_response(record)
  end

  delete '/api/contacts/:id' do |id|
    record = ContactsService.delete(id)
    halt 404, json_error('not found', 404) unless record

    audit!(
      action: 'contact_delete',
      entity_type: 'contact',
      entity_id: id,
      entity_label: contact_label(record),
      details: { category: record['category'] }
    )
    json_response(ok: true, record: record)
  end

  # ---- Journal (??????????? ??????) ----
  get '/api/journal/weeks' do
    halt 503, json_error('journal not configured', 503) unless JournalService.api_available?

    JournalService.cleanup_old_colors(older_than_days: 60)
    json_response(weeks: JournalService.weeks)
  end

  get '/api/journal/week' do
    halt 503, json_error('journal not configured', 503) unless JournalService.api_available?

    start_iso = params[:start].to_s
    halt 400, json_error('start is required (YYYY-MM-DD Monday)', 400) if start_iso.empty?

    begin
      json_response(JournalService.read_week(start_iso))
    rescue StandardError => e
      json_error(e.message, 400)
    end
  end

  get '/api/journal/search' do
    halt 503, json_error('journal not configured', 503) unless JournalService.api_available?
    q = params[:q].to_s.strip
    halt 400, json_error('q required', 400) if q.empty?
    limit = params[:limit].to_i
    limit = 50 if limit <= 0
    json_response(results: JournalService.search(q, limit: limit))
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/journal/cell' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    body = parse_json_body
    date_iso = body['date'].to_s
    time     = body['time'].to_s
    person   = body['person'].to_s
    value    = body['value'].to_s
    old_hint = body.key?('old_value') ? body['old_value'].to_s : nil
    halt 400, json_error('date, time, person required', 400) if date_iso.empty? || time.empty? || person.empty?

    ok, err, old_value = JournalService.write_cell(date_iso, time, person, value, old_value_hint: old_hint)
    if ok
      audit!(
        action: 'journal_update',
        entity_type: 'journal',
        entity_id: "#{date_iso}|#{time}|#{person}",
        entity_label: "#{date_iso} #{time} #{person}",
        field: 'task',
        old_value: old_value,
        new_value: value,
        details: { date: date_iso, time: time, person: person }
      ) if old_value.to_s != value.to_s
      json_response(ok: true, date: date_iso, time: time, person: person, value: value)
    else
      json_error(err.to_s, 502)
    end
  end

  post '/api/journal/next-week' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    ok, result = JournalService.create_next_week
    if ok
      json_response(ok: true, start: result[:start], sheet: result[:sheet])
    else
      json_error(result.to_s, 400)
    end
  end

  get '/api/journal/cell-audit' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    date_iso = params[:date].to_s
    time = params[:time].to_s
    person = params[:person].to_s
    halt 400, json_error('date, time, person required', 400) if date_iso.empty? || time.empty? || person.empty?

    entity_id = "#{date_iso}|#{time}|#{person}"
    logs = AuditLogService.list(limit: 1, entity_type: 'journal', entity_id: entity_id)
    json_response(log: logs.first)
  end

  post '/api/journal/column' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    body = parse_json_body
    start_iso = body['start'].to_s
    name = body['name'].to_s
    halt 400, json_error('start and name required', 400) if start_iso.empty? || name.strip.empty?

    result = JournalService.add_person_column(start_iso, name)
    audit!(
      action: 'journal_column_add',
      entity_type: 'journal',
      entity_id: "#{start_iso}|#{result[:person]}",
      entity_label: result[:sheet].to_s,
      field: 'column',
      old_value: result[:exists] ? result[:person] : '',
      new_value: result[:person],
      details: { start: start_iso, sheet: result[:sheet], existed: result[:exists] }
    ) unless result[:exists]
    json_response(ok: true, **result)
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  post '/api/journal/enable-saturday' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    body = parse_json_body
    start_iso = body['start'].to_s
    halt 400, json_error('start required', 400) if start_iso.empty?

    result = JournalService.enable_saturday(start_iso)
    audit!(
      action: 'journal_enable_saturday',
      entity_type: 'journal',
      entity_id: start_iso,
      entity_label: start_iso,
      field: 'saturday',
      old_value: result[:already_exists] ? 'yes' : 'no',
      new_value: 'yes',
      details: { start: start_iso, saturday: result[:date] }
    ) unless result[:already_exists]
    json_response(ok: true, **result)
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  delete '/api/journal/column' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    body = parse_json_body
    start_iso = body['start'].to_s
    name = body['name'].to_s
    halt 400, json_error('start and name required', 400) if start_iso.empty? || name.strip.empty?

    result = JournalService.delete_person_column(start_iso, name)
    audit!(
      action: 'journal_column_delete',
      entity_type: 'journal',
      entity_id: "#{start_iso}|#{result[:person]}",
      entity_label: result[:sheet].to_s,
      field: 'column',
      old_value: result[:person],
      new_value: ''
    )
    json_response(ok: true, **result)
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/journal/columns/rename' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    body = parse_json_body
    start_iso = body['start'].to_s
    mapping = body['mapping']
    halt 400, json_error('start and mapping required', 400) if start_iso.empty? || !mapping.is_a?(Hash)

    result = JournalService.rename_person_columns(start_iso, mapping)
    result[:renamed].each do |item|
      audit!(
        action: 'journal_column_rename',
        entity_type: 'journal',
        entity_id: "#{start_iso}|#{item[:from]}",
        entity_label: result[:sheet].to_s,
        field: 'column_name',
        old_value: item[:from],
        new_value: item[:to]
      )
    end
    json_response(ok: true, **result)
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/journal/cell-color' do
    halt 503, json_error('journal not configured', 503) unless JournalService.enabled?

    body = parse_json_body
    cells = body['cells']
    halt 400, json_error('cells array required', 400) unless cells.is_a?(Array) && !cells.empty?

    saved = []
    cells.each do |c|
      date_iso = c['date'].to_s
      time_slot = c['time'].to_s
      person = c['person'].to_s
      color = c['color'].to_s
      next if date_iso.empty? || time_slot.empty? || person.empty?

      JournalService.write_cell_color(date_iso, time_slot, person, color)
      saved << { date: date_iso, time: time_slot, person: person, color: color }
    end

    json_response(ok: true, saved: saved.size)
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  # ---- Algorithms (??????????? ???????) ----
  get '/api/algorithms' do
    list = AlgorithmsService::ALGORITHMS.map do |key, data|
      { key: key, title: data[:text], steps_count: data[:steps].size }
    end
    json_response(items: list)
  end

  get '/api/algorithms/:key' do |key|
    data = AlgorithmsService::ALGORITHMS[key]
    halt 404, json_error('algorithm not found', 404) unless data

    json_response(
      key: key,
      title: data[:text],
      steps: data[:steps].map { |s| { title: s[:title], text: s[:text] } }
    )
  end

  # ---- Devices Info (??????? ?????) ----
  get '/api/devices' do
    json_response(tree: DevicesInfoService::TREE)
  end

  # ---- Metering devices / UUTE ----
  get '/api/metering/gspo' do
    page = [params[:page].to_i, 0].max
    query = params[:q].to_s.strip
    json_response(UuteService.list_gspo(page: page, query: query))
  end

  get '/api/metering/gspo/export' do
    require_not_water_payment_only!
    require 'spreadsheet'
    require 'tempfile'
    require 'date'

    records = UuteService.export_all
    halt 404, json_error('Нет объектов для выгрузки', 404) if records.empty?

    Spreadsheet.client_encoding = 'UTF-8'
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: 'Приборы учета ГСПО')

    columns = UuteService::EXPORT_COLUMNS
    columns.each_with_index { |(_, label), i| sheet[0, i] = label }
    sheet.row(0).default_format = Spreadsheet::Format.new(weight: :bold)

    wrap_format = Spreadsheet::Format.new(text_wrap: true, width: 40)
    thin_format = Spreadsheet::Format.new(width: 12)

    columns.each_with_index do |(key, _), col_idx|
      case key
      when 'name', 'address'
        sheet.column(col_idx).default_format = wrap_format
      when 'nearest_verification_date', 'admit_until', 'date_input_uute', 'date_output_uute',
           'calculator_verification_date', 'flowmeter_verification_date_1', 'flowmeter_verification_date_2',
           'temp_sensor_verification_date_1', 'temp_sensor_verification_date_2',
           'pressure_sensor_verification_date_1', 'pressure_sensor_verification_date_2',
           'registration_date', 'check_date', 'readings_date'
        sheet.column(col_idx).default_format = thin_format
      end
    end

    records.each_with_index do |record, idx|
      columns.each_with_index do |(key, _), col_idx|
        val = record[key.to_sym]
        sheet[idx + 1, col_idx] = (val.nil? || val.to_s.strip.empty?) ? '' : val.to_s.strip
      end
    end

    date = Date.today.strftime('%Y%m%d')
    filename = "Приборы_учета_ГСПО_#{date}.xls"
    tmpfile = Tempfile.new(['gspo_export', '.xls'])
    tmpfile.close
    book.write(tmpfile.path)

    audit!(
      action: 'metering_export',
      entity_type: 'metering',
      entity_label: "Выгрузка ГСПО (#{records.size} объектов)"
    )

    send_file tmpfile.path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  end

  get '/api/metering/gspo/:id' do |id|
    record = UuteService.find(id)
    halt 404, json_error('not found', 404) unless record

    json_response(record)
  end

  post '/api/metering/gspo/:id/arshin-apply' do |id|
    body = parse_json_body
    item = body['item']
    halt 400, json_error('item required', 400) unless item.is_a?(Hash)

    serial_key = body['serial_key'].to_s
    registry_url = item['registry_url'].to_s.strip
    registry_url = ArshinService.registry_link_for_item(item) if registry_url.empty?
    before = UuteService.find(id)
    old_check = arshin_checks_from_record(before)[serial_key]
    result = UuteService.apply_arshin_meter_check(
      id,
      serial_key: serial_key,
      item: item,
      save_pdf: body['save_pdf'] != false
    )
    after = UuteService.find(id)
    new_check = arshin_checks_from_record(after)[serial_key]
    new_check = arshin_item_audit_data(item, registry_url: registry_url, yadisk_path: result[:yadisk_path]) if new_check.nil? || new_check.empty?
    audit!(
      action: 'metering_arshin_apply',
      entity_type: 'metering',
      entity_id: id.to_s,
      entity_label: billing_label(after),
      field: arshin_meter_label(serial_key),
      old_value: arshin_audit_summary(old_check),
      new_value: arshin_audit_summary(new_check),
      details: {
        serial_key: serial_key,
        save_pdf: body['save_pdf'] != false,
        pdf_saved: result[:pdf_saved],
        pdf_error: result[:pdf_error],
        yadisk_path: result[:yadisk_path],
        mi_number: item['mi_number'],
        mit_number: item['mit_number'],
        mit_notation: item['mit_notation'],
        verification_date: item['verification_date'],
        valid_date: item['valid_date'],
        registry_url: registry_url
      }
    )
    json_response(result)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  patch '/api/metering/gspo/:id' do |id|
    payload = parse_json_body
    before = UuteService.find(id)
    record = UuteService.update(id, payload)
    changed_fields = payload.keys.map(&:to_s)
    AuditLogService.record_changes(
      actor: current_user,
      action: 'metering_update',
      entity_type: 'metering',
      entity_id: id.to_s,
      entity_label: billing_label(record),
      before: before || {},
      after: record || {},
      fields: changed_fields,
      ip: request_ip,
      user_agent: request.user_agent
    )
    json_response(record)
  rescue ArgumentError => e
    halt 404, json_error(e.message, 404)
  end

  get '/api/metering/gspo/:id/links' do |id|
    json_response(UuteService.links_for_uute(id))
  end

  get '/api/metering/gspo/:id/admission-act' do |id|
    record = UuteService.find(id)
    halt 404, json_error('not found', 404) unless record

    path, filename = UuteActService.build(record, user: current_user)
    audit!(
      action: 'metering_admission_act_download',
      entity_type: 'metering',
      entity_id: id.to_s,
      entity_label: billing_label(record),
      details: { filename: filename }
    )
    send_file path, filename: filename, type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', disposition: 'attachment'
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  get '/api/contacts/:id/metering-links' do |id|
    json_response(UuteService.links_for_contact(id))
  end

  get '/api/contacts/:id/water-registry' do |id|
    json_response(WaterRegistryService.rows_for_contact(id))
  end

  post '/api/metering/links' do
    body = parse_json_body
    link = UuteService.create_link(
      contact_id: body['contact_id'],
      uute_id: body['uute_id'],
      status: body['status'].to_s.empty? ? 'manual' : body['status']
    )
    audit!(
      action: 'metering_link_create',
      entity_type: 'metering',
      entity_id: body['uute_id'].to_s,
      entity_label: body['contact_id'].to_s,
      details: {
        contact_id: body['contact_id'],
        uute_id: body['uute_id'],
        status: link[:status] || body['status']
      }
    )
    json_response(link: link)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  delete '/api/metering/links' do
    body = parse_json_body
    UuteService.delete_link(contact_id: body['contact_id'], uute_id: body['uute_id'])
    audit!(
      action: 'metering_link_delete',
      entity_type: 'metering',
      entity_id: body['uute_id'].to_s,
      entity_label: body['contact_id'].to_s,
      details: {
        contact_id: body['contact_id'],
        uute_id: body['uute_id']
      }
    )
    json_response(ok: true)
  end

  post '/api/metering/gspo/import' do
    require_billing_access!
    file = params[:file]
    halt 400, json_error('file required', 400) unless file && file[:tempfile]

    result = UuteService.import_file(file[:tempfile].path, filename: file[:filename])
    audit!(
      action: 'metering_import',
      entity_type: 'metering',
      entity_id: '',
      entity_label: file[:filename].to_s,
      details: result
    )
    json_response(result)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  get '/api/metering/water' do
    page = [params[:page].to_i, 0].max
    query = params[:q].to_s.strip
    point = params[:point].to_s.strip
    sort = params[:sort].to_s.strip
    dir = params[:dir].to_s.strip
    payment_from = params[:payment_from].to_s.strip
    payment_to = params[:payment_to].to_s.strip
    application_from = params[:application_from].to_s.strip
    application_to = params[:application_to].to_s.strip
    json_response(
      WaterRegistryService.list(
        page: page, query: query, point: point, sort: sort, dir: dir,
        payment_from: payment_from, payment_to: payment_to,
        application_from: application_from, application_to: application_to
      )
    )
  end

  get '/api/metering/water/phoneogram' do
    require_not_water_payment_only!
    path, filename = WaterPhoneogramService.build(
      payment_from: params[:payment_from],
      payment_to: params[:payment_to],
      signer: params[:signer]
    )
    send_file path, filename: filename, type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', disposition: 'attachment'
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  get '/api/metering/water/disconnected-export' do
    require_not_water_payment_only!
    require 'spreadsheet'
    require 'tempfile'
    require 'date'

    rows = WaterRegistryService.disconnected_points_export
    halt 404, json_error('Нет отключённых точек для выгрузки', 404) if rows.empty?

    Spreadsheet.client_encoding = 'UTF-8'
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: 'Отключённые точки')

    col_size = 20
    num_cols = (rows.size + col_size - 1) / col_size

    (0...num_cols).each do |col_idx|
      sheet[0, col_idx] = "Точка"
      sheet.row(0).set_format(col_idx, Spreadsheet::Format.new(weight: :bold))
    end

    rows.each_with_index do |row, idx|
      col = idx / col_size
      row_in_col = idx % col_size
      sheet[row_in_col + 1, col] = row[:point]
    end

    date = Date.today.strftime('%Y%m%d')
    filename = "Реестр_отключенных_#{date}.xls"
    tmpfile = Tempfile.new(['disconnected', '.xls'])
    tmpfile.close
    book.write(tmpfile.path)

    audit!(
      action: 'water_disconnected_export',
      entity_type: 'summer_water',
      entity_label: "Выгрузка отключённых точек (#{rows.size})"
    )

    send_file tmpfile.path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  end

  get '/api/metering/water/:id' do |id|
    record = WaterRegistryService.find(id)
    halt 404, json_error('not found', 404) unless record

    json_response(record)
  end

  post '/api/metering/water' do
    require_not_water_payment_only!
    record = WaterRegistryService.create(parse_json_body)
    audit!(
      action: 'water_create',
      entity_type: 'summer_water',
      entity_id: record[:id],
      entity_label: water_label(record),
      details: { manual: true }
    )
    json_response(record, 201)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end
  patch '/api/metering/water/:id' do |id|
    body = parse_json_body
    if UsersService.water_payment_only?(current_user)
      keys = body.keys.map(&:to_s)
      halt 403, json_error('access denied', 403) unless keys == ['payment']
    end

    before_record = WaterRegistryService.find(id)
    payment_before = before_record ? before_record[:payment].to_s.strip.downcase : ''
    payment_after = body['payment'].to_s.strip.downcase
    payment_became_yes = body.key?('payment') && payment_after == 'да' && payment_before != 'да'
    if payment_became_yes
      body['payment_date'] = Date.today.iso8601
    end

    record = WaterRegistryService.update(id, body)
    AuditLogService.record_changes(
      actor: current_user,
      action: 'water_update',
      entity_type: 'summer_water',
      entity_id: id,
      entity_label: water_label(record),
      before: before_record,
      after: record,
      fields: body.keys.map(&:to_s),
      ip: request_ip,
      user_agent: request.user_agent
    )

    if payment_became_yes
      MaxNotifyService.notify_water_payment(water_payment_notification(current_user, record))
    end

    json_response(record)
  rescue ArgumentError => e
    halt 404, json_error(e.message, 404)
  end

  post '/api/metering/water/import' do
    require_billing_access!
    file = params[:file]
    halt 400, json_error('file required', 400) unless file && file[:tempfile]

    result = WaterRegistryService.import_file(file[:tempfile].path, filename: file[:filename])
    json_response(result)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  post '/api/metering/water/import-disconnections' do
    require_billing_access!
    file = params[:file]
    halt 400, json_error('file required', 400) unless file && file[:tempfile]
    filename = file[:filename].to_s.dup
    filename.force_encoding(Encoding::UTF_8)
    unless filename.valid_encoding?
      filename = filename.encode(Encoding::UTF_8, Encoding::ASCII_8BIT, invalid: :replace, undef: :replace, replace: '')
    end
    unless filename.downcase.include?('основной файл')
      halt 400, json_error('Неверный файл: в названии должно быть "Основной файл".', 400)
    end

    result = WaterRegistryService.import_disconnections(file[:tempfile].path, filename: filename)
    json_response(result)
  rescue ArgumentError => e
    halt 400, json_error(e.message, 400)
  end

  # ---- Schedule (view-only ?? ????) ----
  get '/api/schedule/people' do
    halt 503, json_error('sheets not configured', 503) unless SheetsService.enabled?

    json_response(people: SheetsService.people, dates: SheetsService.available_dates.map(&:iso8601))
  end

  get '/api/schedule/day' do
    halt 503, json_error('sheets not configured', 503) unless SheetsService.enabled?

    name = params[:name].to_s
    date_str = params[:date].to_s
    halt 400, json_error('name and date required', 400) if name.empty? || date_str.empty?

    date = Date.iso8601(date_str) rescue nil
    halt 400, json_error('invalid date format (need YYYY-MM-DD)', 400) unless date

    tasks = SheetsService.tasks_for(name, date)
    json_response(name: name, date: date.iso8601, tasks: tasks)
  end

  # ---- ARSHIN ----
  get '/api/arshin/years' do
    json_response(years: ArshinService.allowed_years, orgs: ArshinService.org_titles)
  end

  post '/api/arshin/search' do
    halt 503, json_error('arshin disabled', 503) unless ArshinService.enabled?

    body = parse_json_body
    form = {
      'org_title'    => body['org_title'].to_s,
      'year'         => body['year'].to_s,
      'mi_number'    => body['mi_number'].to_s,
      'mit_notation' => body['mit_notation'].to_s
    }
    result = ArshinService.lookup_by_form_detailed(form)
    json_response(
      text: result[:text],
      items: result[:items],
      year: result[:year]
    )
  end

  post '/api/arshin/search-meter' do
    halt 503, json_error('arshin disabled', 503) unless ArshinService.enabled?

    body = parse_json_body
    result = ArshinService.lookup_for_meter(
      serial: body['serial'],
      result_docnum: body['result_docnum'],
      valid_until: body['valid_until'],
      year: body['year'],
      org_title: body['org_title'],
      mit_notation: body['mit_notation'],
      meter_label: body['meter_label'],
      preferred_mit_notation: body['preferred_mit_notation'],
      serial_key: body['serial_key']
    )
    json_response(
      text: result[:text],
      items: result[:items],
      year: result[:year],
      years_tried: result[:years_tried],
      suggested_years: result[:suggested_years],
      used_preferred_type: result[:used_preferred_type]
    )
  end

  post '/api/arshin/pdf' do
    body = parse_json_body
    item = body['item']
    halt 400, json_error('item required', 400) unless item.is_a?(Hash)

    pdf_data = ArshinPdfHelpers.item_to_pdf_data(item)
    base = ArshinPdfHelpers.base_name(pdf_data, serial_key: body['serial_key'])
    path, err = VerificationPdfService.generate(pdf_data, filename: base)
    halt 502, json_error(err.to_s, 502) if path.nil?

    send_file path, filename: File.basename(path), type: 'application/pdf', disposition: 'attachment'
  end

  # ---- Billing (???) ----
  get '/api/billing/objects' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?

    page = [params[:page].to_i, 0].max
    page_size = (params[:page_size] || 50).to_i
    query = params[:q].to_s.strip
    status = params[:status].to_s.strip.downcase
    status = 'active' unless %w[all active inactive].include?(status)
    json_response(BillingService.list_objects(page: page, page_size: page_size, query: query, status: status))
  end

  get '/api/billing/sheets' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    json_response(sheets: BillingService.sheets)
  end

  patch '/api/billing/current-sheet' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    body = parse_json_body
    result = BillingService.set_current_sheet(sheet_id: body['sheet_id'], name: body['name'])
    json_response(sheet: result)
  rescue StandardError => e
    halt 400, json_error(e.message, 400)
  end

  post '/api/billing/next-month' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    unless UsersService.admin?(current_user) || BillingService.user_can_create_month_login?(current_user[:login])
      halt 403, json_error('Недостаточно прав для создания месяца', 403)
    end
    name, err = BillingService.create_next_month
    halt 400, json_error(err, 400) if err
    audit!(
      action: 'billing_next_month_create',
      entity_type: 'billing',
      entity_id: name.to_s,
      entity_label: "Создан месяц: #{name}",
      details: { sheet: name }
    )
    json_response(ok: true, sheet: name)
  end

  delete '/api/billing/sheet/:id' do |id|
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    unless UsersService.admin?(current_user) || BillingService.user_can_create_month_login?(current_user[:login])
      halt 403, json_error('Недостаточно прав для удаления месяца', 403)
    end
    ok, result = BillingService.delete_sheet(id.to_i)
    halt 400, json_error(result, 400) unless ok
    audit!(
      action: 'billing_month_delete',
      entity_type: 'billing',
      entity_id: id.to_s,
      entity_label: "Удален месяц: #{result}",
      details: { sheet: result }
    )
    json_response(ok: true, deleted: result)
  end

  get '/api/billing/search' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?

    query = params[:q].to_s.strip
    halt 400, json_error('query too short', 400) if query.length < 2
    status = params[:status].to_s.strip.downcase
    active_only = status != 'all'

    json_response(
      query: query,
      records: BillingService.find_objects(query, limit: 100, active_only: active_only)
    )
  end

  get '/api/billing/object/:row' do |row|
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?

    details = BillingService.object_details(row.to_i)
    halt 404, json_error('object not found', 404) unless details

    json_response(details)
  end

  patch '/api/billing/object/:row/reading' do |row|
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?

    body = parse_json_body
    value = body['value'].to_s.strip
    date_str = body['date'].to_s.strip
    halt 400, json_error('value and date required', 400) if value.empty? || date_str.empty?
    before_record = BillingService.object_details(row.to_i)

    ok, err = BillingService.write_readings(row.to_i, value, date_str)
    if ok
      after_record = BillingService.object_details(row.to_i)
      audit!(
        action: 'billing_reading_save',
        entity_type: 'billing',
        entity_id: row.to_s,
        entity_label: billing_label(after_record || before_record),
        details: {
          date: date_str,
          input_value: value,
          before_current_date: before_record && before_record[:current_date],
          before_current_value: before_record && before_record[:current_value],
          after_current_date: after_record && after_record[:current_date],
          after_current_value: after_record && after_record[:current_value],
          after_volume_gvs: after_record && after_record[:volume_gvs]
        }
      )
      AuditLogService.record_changes(
        actor: current_user,
        action: 'billing_reading_update',
        entity_type: 'billing',
        entity_id: row.to_s,
        entity_label: billing_label(after_record || before_record),
        before: before_record || {},
        after: after_record || {},
        fields: %w[current_date current_value volume_gvs],
        ip: request_ip,
        user_agent: request.user_agent
      )
      json_response(ok: true)
    else
      json_error(err.to_s, 502)
    end
  end

  patch '/api/billing/object/:row' do |row|
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    body = parse_json_body
    before_record = BillingService.object_details(row.to_i)
    ok, err = BillingService.update_object(row.to_i, body)
    halt 400, json_error(err, 400) unless ok
    after_record = BillingService.object_details(row.to_i)
    audit!(
      action: 'billing_object_save',
      entity_type: 'billing',
      entity_id: row.to_s,
      entity_label: billing_label(after_record || before_record),
      details: {
        fields: body.keys.map(&:to_s),
        before: before_record,
        after: after_record
      }
    )
    AuditLogService.record_changes(
      actor: current_user,
      action: 'billing_object_update',
      entity_type: 'billing',
      entity_id: row.to_s,
      entity_label: billing_label(after_record || before_record),
      before: before_record || {},
      after: after_record || {},
      fields: body.keys.map(&:to_s),
      ip: request_ip,
      user_agent: request.user_agent
    )
    json_response(after_record)
  end

  post '/api/billing/object' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    body = parse_json_body
    record, err = BillingService.create_object(body)
    halt 400, json_error(err, 400) if err
    audit!(
      action: 'billing_object_create',
      entity_type: 'billing',
      entity_id: record[:row].to_s,
      entity_label: billing_label(record),
      details: { sheet: record[:sheet] }
    )
    json_response(record, 201)
  end

  post '/api/billing/import-google' do
    require_billing_access!
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    halt 503, json_error('google billing not configured', 503) unless BillingService.google_configured?

    BillingService.import_all_from_google!
    audit!(
      action: 'billing_import_google',
      entity_type: 'billing',
      entity_id: 'import',
      entity_label: 'Импорт биллинга из Google'
    )
    json_response(ok: true)
  rescue StandardError => e
    halt 502, json_error("import failed: #{e.message}", 502)
  end

  get '/api/billing/export' do
    halt 503, json_error('billing disabled', 503) unless BillingService.enabled?
    status = params[:status].to_s.strip.downcase
    status = 'all' unless %w[all active inactive].include?(status)
    path, filename = BillingService.export_current_sheet(status: status)
    send_file path, filename: filename, type: 'application/vnd.ms-excel', disposition: 'attachment'
  rescue StandardError => e
    halt 502, json_error("export failed: #{e.message}", 502)
  end

  # ---- Calculations (?????? ?? ???????) ----
  post '/api/calc/volume' do
    body = parse_json_body
    form = {
      'h'        => body['h'].to_s,
      'v'        => body['v'].to_s,
      'q'        => body['q'].to_s,
      't_vn'     => body['t_vn'].to_s,
      'v_podval' => body['v_podval'].to_s
    }
    text = VolumeCalcService.volume_calculate_by_form(form)
    json_response(text: text)
  end

  # ---- Fallbacks ----
  not_found do
    if request.path.start_with?('/api/')
      json_error('not found', 404)
    else
      content_type :json
      [404, {}, [JSON.generate(error: 'not found')]]
    end
  end

  error do
    err = env['sinatra.error']
    json_error("#{err.class}: #{err.message}", 500)
  end

  run! if app_file == $PROGRAM_NAME
end
