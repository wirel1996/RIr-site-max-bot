# frozen_string_literal: true

# Хранилище пользователей сайта (логин = фамилия из шапки журнала, пароль PBKDF2-HMAC-SHA256).
# Файл storage/users.json не коммитим (gitignored). Управление через scripts/users_cli.rb.

require 'json'
require 'fileutils'
require 'openssl'
require 'securerandom'
require 'rack/utils'
require 'time'

module UsersService
  module_function

  def users_file_path
    raw = ENV['USERS_FILE'].to_s.strip
    path = raw.empty? ? File.expand_path('../storage/users.json', __dir__) : raw
    File.expand_path(path)
  end
  PBKDF2_ITER = 200_000
  PBKDF2_KEYLEN = 32
  PBKDF2_DIGEST = 'sha256'
  ROLES = %w[limited full admin water_payment].freeze
  PASSWORD_POLICY_TEXT = 'password must be at least 8 chars and contain uppercase, lowercase, and digit'
  BOOTSTRAP_ADMIN_LOGINS = ['голоманский'].freeze

  @mutex = Mutex.new
  @activity_throttle = {}
  ACTIVITY_MIN_INTERVAL = 60 # сек между записями last_seen без смены страницы

  def list
    load_all.map { |u| public_user(u) }
  end

  # Пользователи с заполненной должностью — для выбора «Кто составлял акт».
  def switch_act_authors
    load_all
      .map { |u| public_user(u) }
      .select { |u| !u[:position].to_s.strip.empty? }
      .map do |u|
        name = u[:name].to_s.strip
        display = name.empty? ? u[:login].to_s : name
        { login: u[:login], name: display }
      end
      .sort_by { |u| u[:name].to_s.downcase }
  end

  def resolve_switch_act_author(selected)
    text = selected.to_s.strip
    return nil if text.empty?

    hit = switch_act_authors.find do |a|
      a[:name] == text || normalize(a[:login]) == normalize(text)
    end
    return nil unless hit

    user = find(hit[:login])
    {
      login: hit[:login],
      name: hit[:name],
      position: user ? user[:position].to_s.strip : ''
    }
  end

  def find(login)
    return nil if login.to_s.strip.empty?

    needle = normalize(login)
    load_all.find { |u| normalize(u[:login]) == needle }
  end

  # Возвращает хэш { login:, name: } если пара логин/пароль валидна, иначе nil.
  def authenticate(login, password)
    user = find_by_login_or_email(login)
    return nil unless user
    return nil unless verify_password(password.to_s, user[:password_hash].to_s)

    mark_login(user[:login])
    public_user(find(user[:login]) || user)
  end

  def upsert(login:, name:, password:, role: nil)
    raise ArgumentError, 'login required' if login.to_s.strip.empty?
    validate_password!(password.to_s)

    @mutex.synchronize do
      users = load_all_unlocked
      norm = normalize(login)
      existing = users.find { |u| normalize(u[:login]) == norm }
      if existing
        existing[:name] = name.to_s.strip if name && !name.to_s.strip.empty?
        existing[:password_hash] = hash_password(password)
        existing[:role] = normalize_role(role, existing[:login]) if role
        existing[:updated_at] = Time.now.to_i
      else
        users << {
          login: login.to_s.strip,
          name: name.to_s.strip,
          password_hash: hash_password(password),
          email: '',
          session_version: 1,
          role: normalize_role(role, login),
          created_at: Time.now.to_i
        }
      end
      save_all(users)
      public_user(users.find { |u| normalize(u[:login]) == norm })
    end
  end

  def update(login:, new_login: nil, name: nil, role: nil, password: nil, email: nil, position: nil)
    raise ArgumentError, 'login required' if login.to_s.strip.empty?
    validate_password!(password.to_s) if password && !password.to_s.empty?

    @mutex.synchronize do
      users = load_all_unlocked
      norm = normalize(login)
      existing = users.find { |u| normalize(u[:login]) == norm }
      raise ArgumentError, 'user not found' unless existing

      clean_login = new_login.to_s.strip
      if !clean_login.empty? && normalize(clean_login) != norm
        raise ArgumentError, 'login already exists' if users.any? { |u| normalize(u[:login]) == normalize(clean_login) }

        existing[:login] = clean_login
      end
      existing[:name] = name.to_s.strip if name && !name.to_s.strip.empty?
      existing[:email] = normalize_email(email) unless email.nil?
      existing[:position] = position.to_s.strip unless position.nil?
      existing[:role] = normalize_role(role, existing[:login]) if role
      existing[:password_hash] = hash_password(password) if password && !password.to_s.empty?
      existing[:updated_at] = Time.now.to_i
      save_all(users)
      public_user(existing)
    end
  end

  def delete(login)
    @mutex.synchronize do
      users = load_all_unlocked
      norm = normalize(login)
      before = users.length
      users.reject! { |u| normalize(u[:login]) == norm }
      save_all(users)
      users.length < before
    end
  end

  def public_user(user)
    return nil unless user

    {
      login: user[:login],
      name: user[:name],
      email: user[:email].to_s,
      position: user[:position].to_s,
      session_version: user[:session_version].to_i,
      role: effective_role(user),
      created_at: user[:created_at],
      updated_at: user[:updated_at],
      last_login_at: user[:last_login_at],
      last_seen_at: user[:last_seen_at],
      last_seen_page: user[:last_seen_page].to_s
    }
  end

  def admin?(user_or_login)
    user = user_or_login.is_a?(Hash) ? user_or_login : find(user_or_login)
    effective_role(user) == 'admin'
  end

  def billing_allowed?(user_or_login)
    user = user_or_login.is_a?(Hash) ? user_or_login : find(user_or_login)
    %w[admin full].include?(effective_role(user))
  end

  def water_payment_only?(user_or_login)
    user = user_or_login.is_a?(Hash) ? user_or_login : find(user_or_login)
    effective_role(user) == 'water_payment'
  end

  def hash_password(password)
    salt = SecureRandom.hex(16)
    raw = OpenSSL::PKCS5.pbkdf2_hmac(password.to_s, salt, PBKDF2_ITER, PBKDF2_KEYLEN, PBKDF2_DIGEST)
    "pbkdf2:#{PBKDF2_ITER}:#{salt}:#{raw.unpack1('H*')}"
  end

  def verify_password(password, stored)
    parts = stored.split(':', 4)
    return false unless parts.length == 4 && parts[0] == 'pbkdf2'

    iter = parts[1].to_i
    salt = parts[2]
    expected = parts[3]
    return false if iter <= 0 || salt.empty? || expected.empty?

    actual = OpenSSL::PKCS5.pbkdf2_hmac(password.to_s, salt, iter, PBKDF2_KEYLEN, PBKDF2_DIGEST).unpack1('H*')
    Rack::Utils.secure_compare(actual, expected)
  end

  def normalize(login)
    s = login.to_s
    s = s.dup.force_encoding('UTF-8') unless s.encoding == Encoding::UTF_8
    s = s.scrub('') unless s.valid_encoding?
    s.strip.downcase
  end

  def normalize_role(role, login = nil)
    return 'admin' if BOOTSTRAP_ADMIN_LOGINS.include?(normalize(login))

    value = role.to_s.strip.downcase
    value = 'full' if value.empty? || value == 'user'
    ROLES.include?(value) ? value : 'full'
  end

  def effective_role(user)
    normalize_role(user&.dig(:role), user&.dig(:login))
  end

  def mark_login(login)
    @mutex.synchronize do
      users = load_all_unlocked
      norm = normalize(login)
      existing = users.find { |u| normalize(u[:login]) == norm }
      return unless existing

      now = Time.now.to_i
      existing[:last_login_at] = now
      existing[:last_seen_at] = now
      existing[:updated_at] ||= now
      save_all(users)
    end
  end

  def mark_activity(login, page: nil, force: false)
    @mutex.synchronize do
      users = load_all_unlocked
      norm = normalize(login)
      existing = users.find { |u| normalize(u[:login]) == norm }
      return nil unless existing

      now = Time.now.to_i
      clean_page = nil
      unless page.nil?
        clean_page = page.to_s.strip
        clean_page = clean_page[0, 120]
        clean_page = nil if clean_page.empty?
      end
      page_changed = clean_page && clean_page != existing[:last_seen_page].to_s
      last_write = @activity_throttle[norm].to_i
      unless force || page_changed || last_write.zero? || (now - last_write) >= ACTIVITY_MIN_INTERVAL
        return public_user(existing)
      end

      existing[:last_seen_at] = now
      existing[:last_seen_page] = clean_page if clean_page
      existing[:updated_at] ||= now
      save_all(users)
      @activity_throttle[norm] = now
      public_user(existing)
    end
  end

  def request_password_reset(login_or_email)
    user = find_by_login_or_email(login_or_email)
    return nil unless user

    token = SecureRandom.hex(24)
    token_hash = OpenSSL::Digest::SHA256.hexdigest(token)
    expires_at = Time.now.to_i + 3600

    @mutex.synchronize do
      users = load_all_unlocked
      existing = users.find { |u| normalize(u[:login]) == normalize(user[:login]) }
      next unless existing
      existing[:reset_token_hash] = token_hash
      existing[:reset_expires_at] = expires_at
      existing[:updated_at] = Time.now.to_i
      save_all(users)
    end

    { login: user[:login], email: user[:email].to_s, token: token, expires_at: expires_at }
  end

  def reset_password(token, new_password)
    t = token.to_s.strip
    return false if t.empty?
    validate_password!(new_password.to_s)
    token_hash = OpenSSL::Digest::SHA256.hexdigest(t)
    now = Time.now.to_i

    @mutex.synchronize do
      users = load_all_unlocked
      existing = users.find do |u|
        u[:reset_token_hash].to_s == token_hash && u[:reset_expires_at].to_i >= now
      end
      return false unless existing

      existing[:password_hash] = hash_password(new_password)
      existing[:session_version] = existing[:session_version].to_i + 1
      existing[:reset_token_hash] = nil
      existing[:reset_expires_at] = nil
      existing[:updated_at] = now
      save_all(users)
      true
    end
  end

  def find_by_login_or_email(value)
    raw = value.to_s.strip
    return nil if raw.empty?
    n_login = normalize(raw)
    n_email = normalize_email(raw)
    load_all.find { |u| normalize(u[:login]) == n_login || normalize_email(u[:email]) == n_email }
  end

  def session_valid?(login, session_version)
    user = find(login)
    return false unless user
    user[:session_version].to_i == session_version.to_i
  end

  def revoke_sessions(login)
    @mutex.synchronize do
      users = load_all_unlocked
      existing = users.find { |u| normalize(u[:login]) == normalize(login) }
      return false unless existing
      existing[:session_version] = existing[:session_version].to_i + 1
      existing[:updated_at] = Time.now.to_i
      save_all(users)
      true
    end
  end

  def load_all
    @mutex.synchronize { load_all_unlocked }
  end

  def load_all_unlocked
    path = users_file_path
    return [] unless File.exist?(path)

    raw = JSON.parse(File.read(path))
    Array(raw).map do |u|
      {
        login: u['login'].to_s,
        name: u['name'].to_s,
        password_hash: u['password_hash'].to_s,
        email: normalize_email(u['email']),
        position: u['position'].to_s,
        role: normalize_role(u['role'], u['login']),
        session_version: (u['session_version'] || 1).to_i,
        reset_token_hash: u['reset_token_hash'].to_s,
        reset_expires_at: u['reset_expires_at'],
        created_at: u['created_at'],
        updated_at: u['updated_at'],
        last_login_at: u['last_login_at'],
        last_seen_at: u['last_seen_at'],
        last_seen_page: u['last_seen_page']
      }
    end
  rescue StandardError
    []
  end

  def save_all(users)
    path = users_file_path
    FileUtils.mkdir_p(File.dirname(path))
    tmp = "#{path}.tmp"
    File.write(tmp, JSON.pretty_generate(users.map { |u| u.transform_keys(&:to_s) }))
    File.rename(tmp, path)
  end

  # ---- Session secret (стабильный между перезапусками) ----
  def validate_password!(password)
    p = password.to_s
    raise ArgumentError, PASSWORD_POLICY_TEXT if p.length < 8
    raise ArgumentError, PASSWORD_POLICY_TEXT unless p.match?(/[A-Z]/)
    raise ArgumentError, PASSWORD_POLICY_TEXT unless p.match?(/[a-z]/)
    raise ArgumentError, PASSWORD_POLICY_TEXT unless p.match?(/\d/)
  end
  private_class_method :validate_password!

  def normalize_email(email)
    email.to_s.strip.downcase
  end
  private_class_method :normalize_email

  SESSION_SECRET_FILE = File.expand_path('../storage/session_secret', __dir__)

  def session_secret
    env = ENV['SESSION_SECRET'].to_s
    return env if env.length >= 32

    if File.exist?(SESSION_SECRET_FILE)
      stored = File.read(SESSION_SECRET_FILE).strip
      return stored if stored.length >= 32
    end

    secret = SecureRandom.hex(64)
    FileUtils.mkdir_p(File.dirname(SESSION_SECRET_FILE))
    File.write(SESSION_SECRET_FILE, secret)
    secret
  end
end
