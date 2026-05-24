# frozen_string_literal: true

require 'json'
require 'fileutils'

module AppSettings
  module_function

  def settings_file_path
    raw = ENV['APP_SETTINGS_PATH'].to_s.strip
    path = raw.empty? ? File.expand_path('../storage/app_settings.json', __dir__) : raw
    File.expand_path(path)
  end

  FILE = settings_file_path
  DEFAULTS = {
    'water_payment_notify_user_id' => '117733220',
    'water_payment_notify_user_ids' => ['117733220'],
    'daily_tasks_notify_time' => '08:00',
    'db_backup_enabled' => false,
    'db_backup_email' => '',
    'db_backup_daily_time' => '02:00',
    'db_backup_notify_user_id' => '',
    'object_switch_act_next_number' => 1
  }.freeze

  @mutex = Mutex.new

  def all
    @mutex.synchronize { DEFAULTS.merge(read_unlocked) }
  end

  def get(key)
    all[key.to_s]
  end

  def set(key, value)
    @mutex.synchronize do
      data = DEFAULTS.merge(read_unlocked)
      data[key.to_s] = value
      write_unlocked(data)
      data
    end
  end

  def read_unlocked
    path = settings_file_path
    return {} unless File.exist?(path)

    JSON.parse(File.read(path, encoding: 'UTF-8'))
  rescue StandardError
    {}
  end
  private_class_method :read_unlocked

  def write_unlocked(data)
    path = settings_file_path
    FileUtils.mkdir_p(File.dirname(path))
    tmp = "#{path}.tmp"
    File.write(tmp, JSON.pretty_generate(data), encoding: 'UTF-8')
    File.rename(tmp, path)
  end
  private_class_method :write_unlocked
end
