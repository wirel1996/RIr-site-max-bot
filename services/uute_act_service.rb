# frozen_string_literal: true

require 'cgi'
require 'date'
require 'fileutils'
require 'securerandom'
require 'tmpdir'
require 'zip'
require 'nokogiri'

module UuteActService
  module_function

  TEMPLATE_PATH = File.expand_path('../services/templates/uute_admission_act_template.docx', __dir__)

  SOURCE_VALUES = {
    list_number: '43',
    name: 'ГСПО "Водолей 1"',
    address: 'ул. Сосновая, 8, стр.8',
    contract_number: '1555',
    calculator_type: 'ТВ7-04.1',
    calculator_serial: '20-106742',
    calculator_verification_date: '31.07.2029',
    seal_calculator: '1246298',
    flowmeter_1: 'РС20-12А',
    flowmeter_serial_1: '137495',
    flowmeter_verification_date_1: '05.09.2026',
    seal_flowmeter_1: 'м.п677602/0215653',
    flowmeter_2: 'РС20-12А',
    flowmeter_serial_2: '137494',
    flowmeter_verification_date_2: '05.09.2026',
    seal_flowmeter_2: '0215654',
    temp_sensor_1: 'КТПТР-01',
    temp_sensor_serial_1: '6499',
    temp_sensor_verification_date_1: '05.09.2026',
    seal_temp_sensor_1: '1241574',
    temp_sensor_2: 'КТПТР-01',
    temp_sensor_serial_2: '6499А',
    temp_sensor_verification_date_2: '05.09.2026',
    seal_temp_sensor_2: '0044492',
    pressure_sensor_1: 'СДВ-И',
    pressure_sensor_serial_1: 'А522963',
    pressure_sensor_verification_date_1: '05.09.2027',
    pressure_sensor_2: 'СДВ-И',
    pressure_sensor_serial_2: 'А522964',
    pressure_sensor_verification_date_2: '05.09.2027',
    seal_cut_1: '1248100/1248096',
    seal_cut_2: '1248278/1248098',
    seal_cut_3: '1248097',
    seal_cut_4: '1246574',
    distance: '145/30',
    diameter: '159/57',
    connection_point_number: '152',
    admit_until: '05.09.2026',
    nearest_verification_date: '05.09.2026'
  }.freeze

  REPEATED_REPLACEMENTS = {
    '05.09.2026' => %i[
      flowmeter_verification_date_1
      flowmeter_verification_date_2
      temp_sensor_verification_date_1
      temp_sensor_verification_date_2
      nearest_verification_date
      nearest_verification_date
    ],
    'РС20-12А' => %i[flowmeter_1 flowmeter_2],
    'КТПТР-01' => %i[temp_sensor_1 temp_sensor_2],
    'СДВ-И' => %i[pressure_sensor_1 pressure_sensor_2]
  }.freeze

  def build(record, user:)
    raise ArgumentError, 'Шаблон акта не найден' unless File.exist?(TEMPLATE_PATH)

    date = Date.today
    filename = "Акт_допуска_УУТЭ_ГСПО_#{safe_filename(record[:name] || record['name'])}_#{date.strftime('%Y%m%d')}.docx"
    output_path = File.join(Dir.tmpdir, "#{SecureRandom.hex(8)}_#{filename}")

    Zip::File.open(TEMPLATE_PATH) do |source_zip|
      Zip::File.open(output_path, create: true) do |target_zip|
        source_zip.each do |entry|
          content = entry.get_input_stream.read
          if entry.name == 'word/document.xml'
            content = patch_document(content, record, user, date)
          end
          target_zip.get_output_stream(entry.name) { |stream| stream.write(content) }
        end
      end
    end

    [output_path, filename]
  end

  def patch_document(content, record, user, date)
    doc = Nokogiri::XML(content)
    replacements_left = Hash.new(0)
    REPEATED_REPLACEMENTS.each { |source, fields| replacements_left[source] = fields.dup }

    doc.xpath('//w:t', 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main').each do |node|
      text = node.text
      if replacements_left.key?(text)
        field = replacements_left[text].shift
        node.content = value(record, field) if field
        next
      end

      field = SOURCE_VALUES.find { |key, source| source == text && !REPEATED_REPLACEMENTS.key?(source) }&.first
      node.content = value(record, field) if field
    end

    specialist = specialist_label(user)
    replace_text(doc, 'Специалист ОКЭ Голоманский В.В.', specialist)
    replace_text(doc, '2026', date.year.to_s, once: true)
    doc.to_xml
  end
  private_class_method :patch_document

  def replace_text(doc, source, target, once: false)
    doc.xpath('//w:t', 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main').each do |node|
      next unless node.text == source

      node.content = target
      return if once
    end
  end
  private_class_method :replace_text

  def value(record, field)
    return '' unless field

    v = record[field] || record[field.to_s]
    v.to_s.strip
  end
  private_class_method :value

  def specialist_label(user)
    position = user && user[:position].to_s.strip
    name = user && (user[:name].to_s.strip.empty? ? user[:login].to_s.strip : user[:name].to_s.strip)
    [position, name].reject(&:empty?).join(' ')
  end
  private_class_method :specialist_label

  def safe_filename(value)
    base = value.to_s.strip
    base = 'без_названия' if base.empty?
    base.gsub(/[\\\/:*?"<>|]+/, '_').gsub(/\s+/, '_')[0, 80]
  end
  private_class_method :safe_filename
end
