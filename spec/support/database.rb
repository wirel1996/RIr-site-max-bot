# frozen_string_literal: true

require 'fileutils'
require 'json'

module SpecDatabase
  module_function

  SPEC_DIR = File.expand_path('../../tmp/spec', __dir__).freeze

  DB_ENV_KEYS = {
    'CONTACTS_DB_PATH' => 'contacts.db',
    'UUTE_DB_PATH' => 'uute.db',
    'WATER_REGISTRY_DB_PATH' => 'water_registry.db',
    'AUDIT_LOG_DB_PATH' => 'audit_log.db',
    'JOURNAL_DB_PATH' => 'journal.db'
  }.freeze

  def setup_env!
    FileUtils.mkdir_p(SPEC_DIR)
    ENV['CONTACTS_WEB_ENV'] = 'test'
    ENV['SESSION_SECRET'] = 'spec-session-secret-' + ('x' * 48)
    ENV['USERS_FILE'] = File.join(SPEC_DIR, 'users.json')
    ENV['APP_SETTINGS_PATH'] = File.join(SPEC_DIR, 'app_settings.json')
    ENV['WATER_PHONEOGRAM_TEMPLATE'] = File.expand_path('../../templates/water_phoneogram_template.docx', __dir__)

    DB_ENV_KEYS.each do |key, filename|
      ENV[key] = File.join(SPEC_DIR, filename)
    end
  end

  def reset!
    reset_databases!
    write_app_settings!
  end

  def reset_databases!
    DB_ENV_KEYS.each_value do |filename|
      path = File.join(SPEC_DIR, filename)
      FileUtils.rm_f(path)
      FileUtils.rm_f("#{path}-wal")
      FileUtils.rm_f("#{path}-shm")
    end
  end

  def prepare_suite!
    setup_env! unless @suite_prepared
    FileUtils.mkdir_p(SPEC_DIR)
    bootstrap_users! unless File.exist?(ENV.fetch('USERS_FILE'))
    @suite_prepared = true
  end

  def write_app_settings!
    path = ENV.fetch('APP_SETTINGS_PATH')
    data = {
      'object_switch_act_next_number' => 100,
      'water_payment_notify_user_ids' => [],
      'db_backup_enabled' => false
    }
    File.write(path, JSON.pretty_generate(data))
  end

  def bootstrap_users!
    require_relative '../../services/users_service'

    UsersService.upsert(
      login: 'rspec_admin',
      name: 'RSpec Admin',
      password: 'Test1234#',
      role: 'admin'
    )
    UsersService.update(login: 'rspec_admin', position: 'Контролер ОКЭ')
    UsersService.upsert(
      login: 'rspec_author',
      name: 'RSpec Author',
      password: 'Test1234#',
      role: 'full'
    )
    UsersService.update(login: 'rspec_author', position: 'Инженер')
  end
end
