# frozen_string_literal: true

require 'json'
require 'fileutils'

module AppSettings
  module_function

  FILE = File.expand_path('../storage/app_settings.json', __dir__)
  DEFAULTS = {
    'water_payment_notify_user_id' => '117733220',
    'water_payment_notify_user_ids' => ['117733220'],
    'daily_tasks_notify_time' => '08:00',
    'db_backup_enabled' => false,
    'db_backup_email' => '',
    'db_backup_daily_time' => '02:00',
    'db_backup_notify_user_id' => ''
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
    return {} unless File.exist?(FILE)

    JSON.parse(File.read(FILE, encoding: 'UTF-8'))
  rescue StandardError
    {}
  end
  private_class_method :read_unlocked

  def write_unlocked(data)
    FileUtils.mkdir_p(File.dirname(FILE))
    tmp = "#{FILE}.tmp"
    File.write(tmp, JSON.pretty_generate(data), encoding: 'UTF-8')
    File.rename(tmp, FILE)
  end
  private_class_method :write_unlocked
end
