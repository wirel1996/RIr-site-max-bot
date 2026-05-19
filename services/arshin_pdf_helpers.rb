# frozen_string_literal: true

require_relative 'arshin_service'

module ArshinPdfHelpers
  module_function

  DEVICE_LABELS = {
    'calculator_serial' => 'Вычислитель',
    'flowmeter_serial_1' => 'Расходомер',
    'flowmeter_serial_2' => 'Расходомер',
    'temp_sensor_serial_1' => 'Датчик_температуры',
    'temp_sensor_serial_2' => 'Датчик_температуры',
    'pressure_sensor_serial_1' => 'Датчик_давления',
    'pressure_sensor_serial_2' => 'Датчик_давления'
  }.freeze

  def item_to_pdf_data(item, year_fallback: nil, serial_override: nil)
    item = item.transform_keys(&:to_s) if item.is_a?(Hash)
    serial = (serial_override || item['mi_number']).to_s
    year = (item['_year'] || item['year'] || year_fallback).to_s
    {
      vri_id:            (item['vri_id'] || item['id']).to_s.strip,
      serial:            serial,
      year:              year,
      mit_notation:      item['mit_notation'].to_s,
      mit_title:         item['mit_title'].to_s,
      org_title:         item['org_title'].to_s,
      verification_date: item['verification_date'].to_s,
      valid_date:        item['valid_date'].to_s,
      result_docnum:     item['result_docnum'].to_s,
      applicability:     applicability_label(item['applicability']),
      registry_url:      item['registry_url'].to_s.empty? ? ArshinService.registry_link_for_item(item) : item['registry_url'].to_s
    }
  end

  def applicability_label(value)
    case value
    when true then 'Да'
    when false then 'Нет'
    when 'Да', 'Нет' then value
    else value.to_s
    end
  end

  def base_name(arshin_item, serial_key: nil)
    serial = arshin_item[:serial].to_s.strip
    date = arshin_item[:verification_date].to_s.strip.tr('.', '-')
    vri = arshin_item[:vri_id].to_s.strip
    device = DEVICE_LABELS[serial_key.to_s].to_s.strip

    base =
      if !serial.empty? && !date.empty?
        "Поверка_#{device}_#{serial}_#{date}"
      elsif !serial.empty? && !vri.empty?
        "Поверка_#{device}_#{serial}_#{vri}"
      elsif !vri.empty?
        "Поверка_#{device}_#{vri}"
      else
        "Поверка_#{device}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      end
    base.gsub(/[\\\/:\*\?"<>|]/, '_').gsub(/_{2,}/, '_').sub(/_\z/, '')
  end
end
