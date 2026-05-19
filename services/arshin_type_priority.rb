# frozen_string_literal: true

require_relative '../storage/app_settings'

module ArshinTypePriority
  module_function

  # Базовый пул приоритетов по семействам приборов.
  # Можно расширять по мере появления новых типов.
  FAMILY_POOLS = {
    'calculator' => [],
    'flowmeter' => [
      'Питерфлоу РС',
      'Взлет',
      'ПРЭМ'
    ],
    'temp_sensor' => [
      'КТС-Б'
    ],
    'pressure_sensor' => ['MBS 1700', 'MBS 1750', 'MBS 3000', 'MBS 3050', 'MBS 33', 'MBS 3200', 'MBS 3250', 'MBS 4510']
  }.freeze
  SETTINGS_KEY = 'arshin_type_priority_pools'

  def family_by_serial_key(serial_key)
    key = serial_key.to_s
    return 'calculator' if key.start_with?('calculator_')
    return 'flowmeter' if key.start_with?('flowmeter_')
    return 'temp_sensor' if key.start_with?('temp_sensor_')
    return 'pressure_sensor' if key.start_with?('pressure_sensor_')

    nil
  end

  def pool_for(serial_key)
    family = family_by_serial_key(serial_key)
    return [] if family.nil?
    pools = all_pools
    Array(pools[family]).map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def all_pools
    data = AppSettings.get(SETTINGS_KEY)
    data = {} unless data.is_a?(Hash)
    merged = FAMILY_POOLS.transform_values(&:dup)
    data.each do |family, list|
      next unless merged.key?(family.to_s)
      merged[family.to_s] = Array(list).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    end
    merged
  end

  def ensure_type_for_serial_key(serial_key, type_name)
    family = family_by_serial_key(serial_key)
    return false if family.nil?

    type = type_name.to_s.strip
    return false if type.empty?

    pools = all_pools
    current = Array(pools[family]).map(&:to_s).map(&:strip).reject(&:empty?)
    return false if current.any? { |v| normalize(v) == normalize(type) }

    current << type
    pools[family] = current.uniq
    AppSettings.set(SETTINGS_KEY, pools)
    true
  end

  def normalize(value)
    value.to_s.downcase.gsub(/[[:space:]\-_.]+/, '')
  end
end
