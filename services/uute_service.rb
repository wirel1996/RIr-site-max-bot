# frozen_string_literal: true

require 'json'
require 'date'
require 'spreadsheet'

require_relative '../storage/uute_db'
require_relative 'water_registry_service'
require_relative 'arshin_pdf_helpers'
require_relative 'verification_pdf_service'
require_relative 'arshin_type_priority'
require_relative '../storage/contacts_db'
require_relative 'audit_log_service'
require_relative 'journal_service'
require_relative 'journal_notify_service'
require_relative '../storage/user_profiles'

module UuteService
  module_function

  PAGE_SIZE = 50

  ARSHIN_SERIAL_DATE_FIELDS = {
    'calculator_serial' => 'calculator_verification_date',
    'flowmeter_serial_1' => 'flowmeter_verification_date_1',
    'flowmeter_serial_2' => 'flowmeter_verification_date_2',
    'flowmeter_serial_3' => 'flowmeter_verification_date_3',
    'flowmeter_serial_4' => 'flowmeter_verification_date_4',
    'temp_sensor_serial_1' => 'temp_sensor_verification_date_1',
    'temp_sensor_serial_2' => 'temp_sensor_verification_date_2',
    'temp_sensor_serial_3' => 'temp_sensor_verification_date_3',
    'temp_sensor_serial_4' => 'temp_sensor_verification_date_4',
    'pressure_sensor_serial_1' => 'pressure_sensor_verification_date_1',
    'pressure_sensor_serial_2' => 'pressure_sensor_verification_date_2',
    'pressure_sensor_serial_3' => 'pressure_sensor_verification_date_3',
    'pressure_sensor_serial_4' => 'pressure_sensor_verification_date_4'
  }.freeze

  XLS_COLUMNS = {
    'list_number' => 0,
    'contract_number' => 1,
    'name' => 2,
    'address' => 3,
    'identifier' => 4,
    'input_kind' => 5,
    'merge_note' => 6,
    'note' => 7,
    'not_allowed' => 8,
    'not_allowed_reason' => 9,
    'date_input_uute' => 40,
    'admit_until' => 41,
    'date_output_uute' => 42,
    'output_reason' => 43,
    'act_primary_number' => 44,
    'act_periodic_number' => 45,
    'act_output_number' => 46,
    'registration_date' => 47,
    'dm_installation' => 48,
    'violations' => 49,
    'violation_fixed_date' => 50,
    'verifier' => 52,
    'documents' => 53,
    'operating_time' => 54,
    'project' => 55,
    'project_approval' => 56,
    'act_date' => 57,
    'input_date' => 58,
    'previous_act_date' => 59,
    'inspection_date' => 60,
    'heat_load' => 63,
    'hot_water_load' => 64,
    'ventilation_load' => 65,
    'contract_flow' => 66,
    'distance' => 67,
    'diameter' => 68,
    'connection_point_number' => 69,
    'installation_point' => 70,
    'losses_before_uute' => 71,
    'losses_after_uute' => 72,
    'calculator_type' => 73,
    'flowmeter_1' => 74,
    'flowmeter_2' => 75,
    'flowmeter_3' => 200,
    'flowmeter_4' => 201,
    'temp_sensor_1' => 76,
    'temp_sensor_2' => 77,
    'temp_sensor_3' => 202,
    'temp_sensor_4' => 203,
    'pressure_sensor_1' => 78,
    'pressure_sensor_2' => 79,
    'pressure_sensor_3' => 204,
    'pressure_sensor_4' => 205,
    'calculator_serial' => 80,
    'flowmeter_serial_1' => 81,
    'flowmeter_serial_2' => 82,
    'flowmeter_serial_3' => 206,
    'flowmeter_serial_4' => 207,
    'temp_sensor_serial_1' => 83,
    'temp_sensor_serial_2' => 84,
    'temp_sensor_serial_3' => 208,
    'temp_sensor_serial_4' => 209,
    'pressure_sensor_serial_1' => 85,
    'pressure_sensor_serial_2' => 86,
    'pressure_sensor_serial_3' => 210,
    'pressure_sensor_serial_4' => 211,
    'calculator_verification_date' => 87,
    'flowmeter_verification_date_1' => 88,
    'flowmeter_verification_date_2' => 89,
    'flowmeter_verification_date_3' => 212,
    'flowmeter_verification_date_4' => 213,
    'temp_sensor_verification_date_1' => 90,
    'temp_sensor_verification_date_2' => 91,
    'temp_sensor_verification_date_3' => 214,
    'temp_sensor_verification_date_4' => 215,
    'pressure_sensor_verification_date_1' => 92,
    'pressure_sensor_verification_date_2' => 93,
    'pressure_sensor_verification_date_3' => 216,
    'pressure_sensor_verification_date_4' => 217,
    'nearest_verification_date' => 94,
    'seal_calculator' => 98,
    'seal_flowmeter_1' => 99,
    'seal_flowmeter_2' => 100,
    'seal_temp_sensor_1' => 101,
    'seal_temp_sensor_2' => 102,
    'seal_cut_1' => 103,
    'seal_cut_2' => 104,
    'seal_cut_3' => 105,
    'seal_cut_4' => 106,
    'seal_cut_5' => 218,
    'seal_cut_6' => 219,
    'seals_checked' => 107,
    'system_type' => 110,
    'service_org' => 111,
    'readings_date' => 112,
    'reading_q' => 113,
    'reading_m1' => 114,
    'reading_v1' => 115,
    'reading_m2' => 116,
    'reading_v2' => 117,
    'reading_t1' => 118,
    'reading_t2' => 119,
    'reading_p1' => 120,
    'reading_p2' => 121,
    'accepted_position' => 122,
    'accepted_by' => 123,
    'check_date' => 130,
    'check_violations' => 131,
    'check_violation_fixed_date' => 132,
    'check_note' => 133
  }.freeze

  XLS_HEADERS = {
    'list_number' => ['N п/п', 1],
    'contract_number' => ['Номер договора', 1],
    'name' => ['Наименование', 1],
    'address' => ['Адрес объекта', 1],
    'identifier' => ['Идентификатор', 1],
    'input_kind' => ['первичного/ повторного', 1],
    'merge_note' => ['Примечание в слиянии', 1],
    'note' => ['Примечание', 1],
    'not_allowed' => ['не допускаются', 1],
    'not_allowed_reason' => ['причина', 1],
    'date_input_uute' => ['Дата ввода УУТЭ', 1],
    'admit_until' => ['допуск до по акту', 1],
    'date_output_uute' => ['Дата вывода УУТЭ', 1],
    'output_reason' => ['Причина', 1],
    'act_primary_number' => ['Номер акта (первичный/ повторный ввод)', 1],
    'act_periodic_number' => ['Номер акта (периодическая проверка)', 1],
    'act_output_number' => ['Номер акта (вывод из эксплуатации)', 1],
    'registration_date' => ['Дата регистрации', 1],
    'dm_installation' => ['установка дМ', 1],
    'violations' => ['Нарушения', 1],
    'violation_fixed_date' => ['Дата устранение нарушения', 1],
    'verifier' => ['Поверитель', 1],
    'documents' => ['Документы', 1],
    'operating_time' => ['Наработка', 1],
    'project' => ['Рабочий проект', 1],
    'project_approval' => ['Согласование проекта', 1],
    'act_date' => ['Дата акта от', 1],
    'input_date' => ['Дата ввода', 1],
    'previous_act_date' => ['Дата предыдущего акта', 1],
    'inspection_date' => ['Дата осмотра', 1],
    'heat_load' => ['Нагрузка отопление, Гкал/ч', 1],
    'hot_water_load' => ['Нагрузка ГВС', 1],
    'ventilation_load' => ['Нагрузка вентиляция', 1],
    'contract_flow' => ['Договорной расход, т/ч', 1],
    'distance' => ['расстояние', 1],
    'diameter' => ['диаметр', 1],
    'connection_point_number' => ['Номер точки присоединения ГСПО', 1],
    'installation_point' => ['Точка установки УУТЭ согласно схемы', 1],
    'losses_before_uute' => ['Потери до УУТЭ, Гкал/год', 1],
    'losses_after_uute' => ['Потери после УУТЭ, Гкал/год', 1],
    'calculator_type' => ['Тепловычислитель', 1],
    'flowmeter_1' => ['Расходомер', 1],
    'flowmeter_2' => ['Расходомер', 2],
    'flowmeter_3' => ['Расходомер', 3],
    'flowmeter_4' => ['Расходомер', 4],
    'temp_sensor_1' => ['Датчик температуры', 1],
    'temp_sensor_2' => ['Датчик температуры', 2],
    'temp_sensor_3' => ['Датчик температуры', 3],
    'temp_sensor_4' => ['Датчик температуры', 4],
    'pressure_sensor_1' => ['Датчик давления', 1],
    'pressure_sensor_2' => ['Датчик давления', 2],
    'pressure_sensor_3' => ['Датчик давления', 3],
    'pressure_sensor_4' => ['Датчик давления', 4],
    'calculator_serial' => ['Тепловычислитель №', 1],
    'flowmeter_serial_1' => ['Расходомер №', 1],
    'flowmeter_serial_2' => ['Расходомер №', 2],
    'flowmeter_serial_3' => ['Расходомер №', 3],
    'flowmeter_serial_4' => ['Расходомер №', 4],
    'temp_sensor_serial_1' => ['Датчик температуры №', 1],
    'temp_sensor_serial_2' => ['Датчик температуры №', 2],
    'temp_sensor_serial_3' => ['Датчик температуры №', 3],
    'temp_sensor_serial_4' => ['Датчик температуры №', 4],
    'pressure_sensor_serial_1' => ['Датчик давления №', 1],
    'pressure_sensor_serial_2' => ['Датчик давления №', 2],
    'pressure_sensor_serial_3' => ['Датчик давления №', 3],
    'pressure_sensor_serial_4' => ['Датчик давления №', 4],
    'calculator_verification_date' => ['Дата окончания поверки тепловычислителя', 1],
    'flowmeter_verification_date_1' => ['Дата окончания поверки расходомера', 1],
    'flowmeter_verification_date_2' => ['Дата окончания поверки расходомера', 2],
    'flowmeter_verification_date_3' => ['Дата окончания поверки расходомера', 3],
    'flowmeter_verification_date_4' => ['Дата окончания поверки расходомера', 4],
    'temp_sensor_verification_date_1' => ['Дата окончания поверки датчика температуры', 1],
    'temp_sensor_verification_date_2' => ['Дата окончания поверки датчика температуры', 2],
    'temp_sensor_verification_date_3' => ['Дата окончания поверки датчика температуры', 3],
    'temp_sensor_verification_date_4' => ['Дата окончания поверки датчика температуры', 4],
    'pressure_sensor_verification_date_1' => ['Дата окончания поверки датчика давления', 1],
    'pressure_sensor_verification_date_2' => ['Дата окончания поверки датчика давления', 2],
    'pressure_sensor_verification_date_3' => ['Дата окончания поверки датчика давления', 3],
    'pressure_sensor_verification_date_4' => ['Дата окончания поверки датчика давления', 4],
    'nearest_verification_date' => ['Ближайшая дата поверки', 1],
    'seal_calculator' => ['Пломба тепловычислитель №', 1],
    'seal_flowmeter_1' => ['Пломба расходомер №', 1],
    'seal_flowmeter_2' => ['Пломба расходомер №', 2],
    'seal_temp_sensor_1' => ['Пломба датчик температуры №', 1],
    'seal_temp_sensor_2' => ['Пломба датчик температуры №', 2],
    'seal_cut_1' => ['Пломба врезка №1', 1],
    'seal_cut_2' => ['Пломба врезка №2', 1],
    'seal_cut_3' => ['Пломба врезка №3', 1],
    'seal_cut_4' => ['Пломба врезка №4', 1],
    'seal_cut_5' => ['Пломба врезка №5', 1],
    'seal_cut_6' => ['Пломба врезка №6', 1],
    'seals_checked' => ['Пломбы сверены', 1],
    'system_type' => ['тип системы закрытая /открытая', 1],
    'service_org' => ['обслуживающая организация', 1],
    'readings_date' => ['Дата показаний', 1],
    'reading_q' => ['Q', 1],
    'reading_m1' => ['M1', 1],
    'reading_v1' => ['V1', 1],
    'reading_m2' => ['M2', 1],
    'reading_v2' => ['V2', 1],
    'reading_t1' => ['t1', 1],
    'reading_t2' => ['t2', 1],
    'reading_p1' => ['P1', 1],
    'reading_p2' => ['P2', 1],
    'accepted_position' => ['должность', 1],
    'accepted_by' => ['Принимал', 1],
    'check_date' => ['Дата проверки', 1],
    'check_violations' => ['Нарушения', 2],
    'check_violation_fixed_date' => ['Дата устранение нарушения', 2],
    'check_note' => ['Примечание', 2]
  }.freeze

  DATE_COLUMNS = (
    [40, 41, 42, 47, 50, 57, 58, 59, 60, 61, 62, 87, 88, 89, 90, 91, 92, 93, 94, 95, 97, 112, 124, 125, 130, 132, 137,
     212, 213, 214, 215, 216, 217]
  ).freeze
  DATE_FIELDS = %w[
    date_input_uute admit_until date_output_uute registration_date violation_fixed_date
    act_date input_date previous_act_date inspection_date calculator_verification_date
    flowmeter_verification_date_1 flowmeter_verification_date_2 flowmeter_verification_date_3 flowmeter_verification_date_4
    temp_sensor_verification_date_1 temp_sensor_verification_date_2 temp_sensor_verification_date_3 temp_sensor_verification_date_4
    pressure_sensor_verification_date_1 pressure_sensor_verification_date_2 pressure_sensor_verification_date_3 pressure_sensor_verification_date_4
    nearest_verification_date readings_date check_date check_violation_fixed_date
  ].freeze

  def enabled?
    UuteDB.with_db { |db| db.get_first_row('SELECT 1 FROM uute_objects LIMIT 1') }
    true
  rescue StandardError
    false
  end

  def list(category: nil, page:, query: nil)
    offset = page.to_i * PAGE_SIZE
    q = query.to_s.strip
    cat = category.to_s.strip
    UuteDB.with_db do |db|
      total = UuteDB.count(db, category: cat, query: q)
      records = UuteDB.list(db, category: cat, limit: PAGE_SIZE, offset: offset, query: q).map { |row| public_row(row) }
      { category: cat, page: page.to_i, page_size: PAGE_SIZE, total: total, query: q, records: records, last_import: UuteDB.last_import(db) }
    end
  end

  def create(category, attrs)
    object_id = attrs['object_id'].to_s.strip
    raise ArgumentError, 'object_id обязателен' if object_id.empty?

    object = ContactsDB.with_db { |db| ContactsDB.find_registry_object(db, object_id.to_i) }
    raise ArgumentError, 'registry_object не найден' unless object

    allowed = editable_fields
    values = { 'category' => category.to_s, 'object_id' => object_id.to_i }
    attrs.each do |key, value|
      k = key.to_s
      next unless allowed.include?(k)
      values[k] = value.to_s.strip
    end

    values['source_key'] = "manual:#{category}:#{object_id}"
    values['periods_json'] = JSON.generate([])
    values['raw_json'] = JSON.generate(values)

    computed_nearest = computed_nearest_verification(values)
    values['nearest_verification_date'] = computed_nearest unless computed_nearest.empty?

    id = UuteDB.with_db { |db| UuteDB.create(db, values) }
    find(id)
  end

  EXPORT_COLUMNS = [
    ['list_number', 'Номер по списку'],
    ['contract_number', 'Номер договора'],
    ['name', 'Наименование'],
    ['address', 'Адрес объекта'],
    ['identifier', 'Идентификатор'],
    ['input_kind', 'Первичный/повторный'],
    ['date_input_uute', 'Дата ввода УУТЭ'],
    ['commercial_accounting', 'Введен в коммерческий учет'],
    ['admit_until', 'Допуск до'],
    ['date_output_uute', 'Дата вывода УУТЭ'],
    ['output_reason', 'Причина вывода'],
    ['act_primary_number', 'Номер акта ввода'],
    ['act_periodic_number', 'Номер акта проверки'],
    ['registration_date', 'Дата регистрации'],
    ['violations', 'Нарушения'],
    ['verifier', 'Поверитель'],
    ['documents', 'Документы'],
    ['heat_load', 'Нагрузка отопление'],
    ['hot_water_load', 'Нагрузка ГВС'],
    ['ventilation_load', 'Нагрузка вентиляция'],
    ['contract_flow', 'Договорной расход'],
    ['distance', 'Расстояние'],
    ['diameter', 'Диаметр'],
    ['connection_point_number', 'Номер точки присоединения'],
    ['installation_point', 'Точка установки УУТЭ'],
    ['system_type', 'Тип системы'],
    ['service_org', 'Обслуживающая организация'],
    ['calculator_type', 'Тепловычислитель'],
    ['calculator_serial', 'Тепловычислитель №'],
    ['calculator_verification_date', 'Дата окончания поверки тепловычислителя'],
    ['flowmeter_1', 'Расходомер 1'],
    ['flowmeter_serial_1', 'Расходомер 1 №'],
    ['flowmeter_verification_date_1', 'Дата окончания поверки расходомера 1'],
    ['flowmeter_2', 'Расходомер 2'],
    ['flowmeter_serial_2', 'Расходомер 2 №'],
    ['flowmeter_verification_date_2', 'Дата окончания поверки расходомера 2'],
    ['flowmeter_3', 'Расходомер 3'],
    ['flowmeter_serial_3', 'Расходомер 3 №'],
    ['flowmeter_verification_date_3', 'Дата окончания поверки расходомера 3'],
    ['flowmeter_4', 'Расходомер 4'],
    ['flowmeter_serial_4', 'Расходомер 4 №'],
    ['flowmeter_verification_date_4', 'Дата окончания поверки расходомера 4'],
    ['temp_sensor_1', 'Датчик температуры 1'],
    ['temp_sensor_serial_1', 'Датчик температуры 1 №'],
    ['temp_sensor_verification_date_1', 'Дата окончания поверки датчика температуры 1'],
    ['temp_sensor_2', 'Датчик температуры 2'],
    ['temp_sensor_serial_2', 'Датчик температуры 2 №'],
    ['temp_sensor_verification_date_2', 'Дата окончания поверки датчика температуры 2'],
    ['temp_sensor_3', 'Датчик температуры 3'],
    ['temp_sensor_serial_3', 'Датчик температуры 3 №'],
    ['temp_sensor_verification_date_3', 'Дата окончания поверки датчика температуры 3'],
    ['temp_sensor_4', 'Датчик температуры 4'],
    ['temp_sensor_serial_4', 'Датчик температуры 4 №'],
    ['temp_sensor_verification_date_4', 'Дата окончания поверки датчика температуры 4'],
    ['pressure_sensor_1', 'Датчик давления 1'],
    ['pressure_sensor_serial_1', 'Датчик давления 1 №'],
    ['pressure_sensor_verification_date_1', 'Дата окончания поверки датчика давления 1'],
    ['pressure_sensor_2', 'Датчик давления 2'],
    ['pressure_sensor_serial_2', 'Датчик давления 2 №'],
    ['pressure_sensor_verification_date_2', 'Дата окончания поверки датчика давления 2'],
    ['pressure_sensor_3', 'Датчик давления 3'],
    ['pressure_sensor_serial_3', 'Датчик давления 3 №'],
    ['pressure_sensor_verification_date_3', 'Дата окончания поверки датчика давления 3'],
    ['pressure_sensor_4', 'Датчик давления 4'],
    ['pressure_sensor_serial_4', 'Датчик давления 4 №'],
    ['pressure_sensor_verification_date_4', 'Дата окончания поверки датчика давления 4'],
    ['nearest_verification_date', 'Ближайшая поверка'],
    ['seal_calculator', 'Пломба тепловычислитель №'],
    ['seal_flowmeter_1', 'Пломба расходомер 1 №'],
    ['seal_flowmeter_2', 'Пломба расходомер 2 №'],
    ['seal_temp_sensor_1', 'Пломба датчик температуры 1 №'],
    ['seal_temp_sensor_2', 'Пломба датчик температуры 2 №'],
    ['seal_cut_1', 'Пломба врезка №1'],
    ['seal_cut_2', 'Пломба врезка №2'],
    ['seal_cut_3', 'Пломба врезка №3'],
    ['seal_cut_4', 'Пломба врезка №4'],
    ['seal_cut_5', 'Пломба врезка №5'],
    ['seal_cut_6', 'Пломба врезка №6'],
    ['seals_checked', 'Пломбы сверены'],
    ['readings_date', 'Дата показаний'],
    ['reading_q', 'Q'],
    ['reading_m1', 'M1'],
    ['reading_v1', 'V1'],
    ['reading_m2', 'M2'],
    ['reading_v2', 'V2'],
    ['reading_t1', 't1'],
    ['reading_t2', 't2'],
    ['reading_p1', 'P1'],
    ['reading_p2', 'P2'],
    ['accepted_by', 'Принимал'],
    ['check_date', 'Дата проверки'],
    ['check_violations', 'Нарушения'],
    ['check_note', 'Примечание'],
  ].freeze

  def export_all(category: nil)
    UuteDB.with_db do |db|
      records = category.to_s.empty? ? UuteDB.all_for_category(db, 'gspo') : UuteDB.all_for_category(db, category.to_s)
      records.map { |row| public_row(row) }
    end
  end

  def find(id)
    UuteDB.with_db do |db|
      row = UuteDB.find(db, id)
      row && public_row(row, detail: true)
    end
  end

  ACT_SUBMIT_FIELDS = %w[
    date_input_uute commercial_accounting admit_until date_output_uute output_reason
    act_primary_number act_periodic_number registration_date violations project
    seal_calculator seal_flowmeter_1 seal_flowmeter_2 seal_flowmeter_3 seal_flowmeter_4
    seal_temp_sensor_1 seal_temp_sensor_2 seal_temp_sensor_3 seal_temp_sensor_4
    seal_cut_1 seal_cut_2 seal_cut_3 seal_cut_4
    readings_date reading_q reading_m1 reading_v1 reading_m2 reading_v2
    reading_t1 reading_t2 reading_p1 reading_p2 accepted_by extra_seals_json
  ].freeze

  SEAL_FLOWMETER_KEYS = (1..4).map { |i| "seal_flowmeter_#{i}" }.freeze
  SEAL_TEMP_KEYS = (1..4).map { |i| "seal_temp_sensor_#{i}" }.freeze
  FLOWMETER_SERIAL_KEYS = (1..4).map { |i| "flowmeter_serial_#{i}" }.freeze
  TEMP_SERIAL_KEYS = (1..4).map { |i| "temp_sensor_serial_#{i}" }.freeze

  def people_list
    names = {}
    begin
      weeks = JournalService.weeks
      target = weeks.find { |w| w[:contains_today] } || weeks.last
      week_data = target ? JournalService.read_week(target[:start].to_s) : nil
      Array(week_data && week_data[:people]).each do |person|
        key = JournalNotifyService.normalize_person_name(person)
        names[key] = true unless key.empty?
      end
    rescue StandardError
      # journal optional
    end
    UserProfiles.each_user do |_uid, profile|
      n = JournalNotifyService.normalize_person_name(profile['name'])
      names[n] = true unless n.empty?
    end
    names.keys.sort
  end

  def field_history(id, field:, limit: 20)
    safe_limit = [[limit.to_i, 1].max, 100].min
    AuditLogService.list(
      limit: safe_limit,
      entity_type: 'metering',
      entity_id: id.to_s,
      field: field.to_s
    )
  end

  def revert_last_act(id)
    existing = UuteDB.with_db { |db| UuteDB.find(db, id) }
    raise ArgumentError, 'uute not found' unless existing

    logs = AuditLogService.list(
      limit: AuditLogService::MAX_LIMIT,
      entity_type: 'metering',
      entity_id: id.to_s,
      action: 'metering_act_submit'
    )
    raise ArgumentError, 'Нет внесённых актов для отката' if logs.empty?

    last_ts = logs.map { |row| row[:created_at].to_i }.max
    batch = logs.select { |row| row[:created_at].to_i == last_ts }
    restore = batch.each_with_object({}) do |row, memo|
      field = row[:field].to_s
      next if field.empty?

      memo[field] = row[:old_value].to_s
    end
    raise ArgumentError, 'Не удалось определить поля для отката' if restore.empty?

    allowed = (ACT_SUBMIT_FIELDS + %w[periods_json nearest_verification_date]).uniq
    values = restore.each_with_object({}) do |(key, value), memo|
      memo[key] = value if allowed.include?(key)
    end

    UuteDB.with_db do |db|
      assignments = values.keys.map { |key| "#{key} = ?" }.join(', ')
      db.execute(
        "UPDATE uute_objects SET #{assignments}, updated_at = ? WHERE id = ?",
        values.values + [Time.now.to_i, id.to_i]
      )
    end
    WaterRegistryService.sync_verification_from_uute!(id)
    {
      record: find(id),
      reverted_at: last_ts,
      fields: values.keys
    }
  end

  def block_history(id, fields:, limit: 50)
    safe_limit = [[limit.to_i, 1].max, 200].min
    field_set = Array(fields).map(&:to_s).reject(&:empty?).to_h { |f| [f, true] }
    return [] if field_set.empty?

    logs = AuditLogService.list(
      limit: safe_limit,
      entity_type: 'metering',
      entity_id: id.to_s
    )
    logs.select { |row| field_set[row[:field].to_s] }
  end

  def submit_act(id, payload)
    existing = UuteDB.with_db { |db| UuteDB.find(db, id) }
    raise ArgumentError, 'uute not found' unless existing

    body = payload.is_a?(Hash) ? payload.transform_keys(&:to_s) : {}
    category = existing['category'].to_s

    values = ACT_SUBMIT_FIELDS.each_with_object({}) do |key, memo|
      next unless body.key?(key)

      memo[key] = body[key].to_s.strip
    end

    validate_act_submit!(existing, values, body)

    reg_year = act_counter_year(values['registration_date'])
    if category == 'gspo'
      values['act_primary_number'] = resolve_act_number(
        category: category,
        kind: 'primary',
        year: reg_year,
        mode: body['act_primary_mode'].to_s,
        manual: body['act_primary_number'].to_s,
        start_from: body['act_primary_start_from']
      )
      values['act_periodic_number'] = resolve_act_number(
        category: category,
        kind: 'periodic',
        year: reg_year,
        mode: body['act_periodic_mode'].to_s,
        manual: body['act_periodic_number'].to_s,
        start_from: body['act_periodic_start_from']
      )
    end

    extra = parse_extra_seals(body['extra_seals'])
    values['extra_seals_json'] = JSON.generate(extra) unless extra.empty?

    if !values['date_output_uute'].to_s.strip.empty? && !values['date_input_uute'].to_s.strip.empty?
      periods = parse_json(existing['periods_json'])
      periods = [] unless periods.is_a?(Array)
      periods << {
        'index' => periods.size + 1,
        'date1' => values['date_input_uute'],
        'date2' => values['date_output_uute']
      }
      values['periods_json'] = JSON.generate(periods)
    end

    computed_nearest = computed_nearest_verification(existing.merge(values))
    values['nearest_verification_date'] = computed_nearest unless computed_nearest.empty?

    UuteDB.with_db do |db|
      assignments = values.keys.map { |key| "#{key} = ?" }.join(', ')
      db.execute(
        "UPDATE uute_objects SET #{assignments}, updated_at = ? WHERE id = ?",
        values.values + [Time.now.to_i, id.to_i]
      )
    end
    WaterRegistryService.sync_verification_from_uute!(id)
    find(id)
  end

  def validate_act_submit!(existing, values, body)
    errors = []
    errors << 'Дата ввода УУТЭ обязательна' if values['date_input_uute'].to_s.strip.empty?
    errors << 'Введен в коммерческий учет обязателен' if values['commercial_accounting'].to_s.strip.empty?
    errors << 'Пломба вычислителя № обязательна' if values['seal_calculator'].to_s.strip.empty?

    (1..4).each do |i|
      serial_key = "flowmeter_serial_#{i}"
      seal_key = "seal_flowmeter_#{i}"
      next if existing[serial_key].to_s.strip.empty?

      errors << "Пломба расходомера #{i} № обязательна" if values[seal_key].to_s.strip.empty?
    end

    extra_seals = parse_extra_seals(body['extra_seals'])
    Array(body['extra_flowmeter_indices']).each do |idx|
      i = idx.to_i
      next if i <= 4
      errors << "Пломба расходомера #{i} № обязательна" if extra_seals.dig('flowmeter', i.to_s).to_s.strip.empty?
    end

    (1..4).each do |i|
      serial_key = "temp_sensor_serial_#{i}"
      seal_key = "seal_temp_sensor_#{i}"
      next if existing[serial_key].to_s.strip.empty?

      errors << "Пломба термометра #{i} № обязательна" if values[seal_key].to_s.strip.empty?
    end

    Array(body['extra_temp_indices']).each do |idx|
      i = idx.to_i
      next if i <= 4
      errors << "Пломба термометра #{i} № обязательна" if extra_seals.dig('temp_sensor', i.to_s).to_s.strip.empty?
    end

    raise ArgumentError, errors.join('; ') unless errors.empty?
  end
  private_class_method :validate_act_submit!

  def resolve_act_number(category:, kind:, year:, mode:, manual:, start_from:)
    mode = mode.to_s.strip
    case mode
    when 'manual'
      manual.to_s.strip
    when 'start_from'
      start = start_from.to_i
      start = 1 if start < 1
      UuteDB.with_db { |db| UuteDB.set_act_counter(db, category: category, kind: kind, year: year, next_number: start) }
      allocated = UuteDB.with_db { |db| UuteDB.allocate_act_number(db, category: category, kind: kind, year: year) }
      bump_counter_from_db_max(db: nil, category: category, kind: kind, year: year, used: allocated)
      allocated.to_s
    else
      UuteDB.with_db do |db|
        max_in_db = UuteDB.max_act_number_in_category(db, category: category, kind: kind, year: year, field: kind)
        row = UuteDB.get_act_counter(db, category: category, kind: kind, year: year)
        counter_next = row ? row['next_number'].to_i : 1
        number = [counter_next, max_in_db + 1].max
        UuteDB.set_act_counter(db, category: category, kind: kind, year: year, next_number: number + 1)
        number.to_s
      end
    end
  end
  private_class_method :resolve_act_number

  def bump_counter_from_db_max(db:, category:, kind:, year:, used:)
    UuteDB.with_db do |d|
      max_in_db = UuteDB.max_act_number_in_category(d, category: category, kind: kind, year: year, field: kind)
      next_num = [used.to_i, max_in_db].max + 1
      UuteDB.set_act_counter(d, category: category, kind: kind, year: year, next_number: next_num)
    end
  end
  private_class_method :bump_counter_from_db_max

  def act_counter_year(registration_date)
    d = parse_ru_date(registration_date)
    d ? d.year : Date.today.year
  end
  private_class_method :act_counter_year

  def parse_extra_seals(value)
    parsed = value.is_a?(Hash) ? value : parse_json(value.is_a?(String) ? value : nil)
    return { 'flowmeter' => {}, 'temp_sensor' => {} } unless parsed.is_a?(Hash)

    {
      'flowmeter' => (parsed['flowmeter'].is_a?(Hash) ? parsed['flowmeter'] : {}).transform_keys(&:to_s),
      'temp_sensor' => (parsed['temp_sensor'].is_a?(Hash) ? parsed['temp_sensor'] : {}).transform_keys(&:to_s)
    }
  end
  module_function :parse_extra_seals

  def exploitation_period_label(date_input, date_output)
    start_d = parse_ru_date(date_input)
    return nil unless start_d

    end_d = parse_ru_date(date_output) || Date.today
    return nil if end_d < start_d

    days = (end_d - start_d).to_i
    format_duration_days(days)
  end
  module_function :exploitation_period_label

  def format_duration_days(total_days)
    return '0 дн.' if total_days <= 0

    years = total_days / 365
    rem = total_days % 365
    months = rem / 30
    days = rem % 30
    parts = []
    parts << "#{years} г." if years.positive?
    parts << "#{months} мес." if months.positive?
    parts << "#{days} дн." if days.positive? || parts.empty?
    parts.join(' ')
  end
  private_class_method :format_duration_days

  def update(id, attrs)
    existing = UuteDB.with_db { |db| UuteDB.find(db, id) }
    raise ArgumentError, 'uute not found' unless existing

    allowed = editable_fields
    forbidden = %w[name address identifier].select { |key| attrs.key?(key) || attrs.key?(key.to_sym) }
    unless forbidden.empty?
      cat_label = (existing['category'] || 'ГСПО').to_s
      raise ArgumentError, "Для #{cat_label} поля name/address/identifier редактируются только через карточку объекта (registry_object)."
    end
    values = attrs.each_with_object({}) do |(key, value), memo|
      k = key.to_s
      next unless allowed.include?(k)

      memo[k] = value.to_s.strip
    end
    return find(id) if values.empty?

    computed_nearest = computed_nearest_verification(existing.merge(values))
    values['nearest_verification_date'] = computed_nearest unless computed_nearest.empty?

    UuteDB.with_db do |db|
      assignments = values.keys.map { |key| "#{key} = ?" }.join(', ')
      db.execute(
        "UPDATE uute_objects SET #{assignments}, updated_at = ? WHERE id = ?",
        values.values + [Time.now.to_i, id.to_i]
      )
    end
    WaterRegistryService.sync_verification_from_uute!(id)
    find(id)
  end

  def apply_arshin_meter_check(id, serial_key:, item:)
    uute_id = id.to_i
    key = serial_key.to_s.strip
    raise ArgumentError, 'serial_key required' if key.empty?
    raise ArgumentError, 'unknown serial_key' unless ARSHIN_SERIAL_DATE_FIELDS.key?(key)
    raise ArgumentError, 'item required' unless item.is_a?(Hash)

    row = UuteDB.with_db { |db| UuteDB.find(db, uute_id) }
    raise ArgumentError, 'uute not found' unless row

    db_serial = row[key].to_s.strip
    arshin_serial = item['mi_number'].to_s.strip
    serial_mismatch = nil
    if !db_serial.empty? && !arshin_serial.empty? && db_serial != arshin_serial
      serial_mismatch = { 'serial_key' => key, 'current' => db_serial, 'found' => arshin_serial }
    end

    item = item.transform_keys(&:to_s)
    applicable = applicability_true?(item['applicability'])
    valid_date = item['valid_date'].to_s.strip
    verification_date = item['verification_date'].to_s.strip
    registry_url = item['registry_url'].to_s.strip
    registry_url = ArshinService.registry_link_for_item(item) if registry_url.empty?

    checks = parse_json(row['arshin_checks_json'])
    checks = {} unless checks.is_a?(Hash)
    check_entry = {
      'valid_date' => valid_date,
      'verification_date' => verification_date,
      'applicability' => applicable,
      'org_title' => item['org_title'].to_s.strip,
      'mi_number' => item['mi_number'].to_s.strip,
      'mit_notation' => item['mit_notation'].to_s.strip,
      'registry_url' => registry_url,
      'checked_at' => Time.now.to_i
    }

    values = { 'arshin_checks_json' => nil }
    date_field = ARSHIN_SERIAL_DATE_FIELDS[key]
    values[date_field] = valid_date unless valid_date.empty?

    checks[key] = check_entry
    values['arshin_checks_json'] = JSON.generate(checks)
    ArshinTypePriority.ensure_type_for_serial_key(key, item['mit_notation'])

    merged = row.merge(values)
    computed_nearest = computed_nearest_verification(merged)
    values['nearest_verification_date'] = computed_nearest unless computed_nearest.empty?

    UuteDB.with_db do |db|
      assignments = values.keys.map { |field| "#{field} = ?" }.join(', ')
      db.execute(
        "UPDATE uute_objects SET #{assignments}, updated_at = ? WHERE id = ?",
        values.values + [Time.now.to_i, uute_id]
      )
    end
    WaterRegistryService.sync_verification_from_uute!(uute_id)

    record = find(uute_id)
    {
      record: record,
      applicability: applicable,
      serial_mismatch: serial_mismatch
    }
  end

  def applicability_true?(value)
    value == true || value.to_s.strip.downcase == 'да'
  end
  private_class_method :applicability_true?

  def links_for_contact(contact_id)
    contact = ContactsDB.with_db { |db| ContactsDB.find_by_id(db, contact_id) }
    return { links: [], candidates: [] } unless contact

    links = UuteDB.with_db { |db| UuteDB.links_for_contact(db, contact_id) }
    linked = links.map { |link| link_with_uute(link) }.compact
    linked_ids = linked.map { |item| item[:uute]&.dig(:id).to_i }
    {
      links: linked,
      candidates: uute_candidates_for_contact(contact, exclude_ids: linked_ids)
    }
  end

  def links_for_uute(uute_id)
    uute = UuteDB.with_db { |db| UuteDB.find(db, uute_id) }
    return { links: [], candidates: [] } unless uute

    links = UuteDB.with_db { |db| UuteDB.links_for_uute(db, uute_id) }
    linked = links.map { |link| link_with_contact(link) }.compact
    linked_ids = linked.map { |item| item[:contact]&.dig('id').to_i }
    {
      links: linked,
      candidates: contact_candidates_for_uute(uute, exclude_ids: linked_ids)
    }
  end

  def create_link(contact_id:, uute_id:, status: 'manual')
    contact = ContactsDB.with_db { |db| ContactsDB.find_by_id(db, contact_id) }
    uute = UuteDB.with_db { |db| UuteDB.find(db, uute_id) }
    raise ArgumentError, 'contact not found' unless contact
    raise ArgumentError, 'uute not found' unless uute

    match = match_contact_uute(contact, uute)
    UuteDB.with_db do |db|
      UuteDB.create_or_update_link(
        db,
        uute_id: uute_id,
        contact_id: contact_id,
        status: status,
        match_score: match[:score],
        match_reason: match[:reason]
      )
    end
  end

  def delete_link(contact_id:, uute_id:)
    UuteDB.with_db { |db| UuteDB.delete_link(db, uute_id: uute_id, contact_id: contact_id) }
  end

  def auto_link!
    contacts = ContactsDB.with_db do |db|
      db.execute("SELECT * FROM contacts WHERE category = 'gspo'")
    end
    uutes = UuteDB.with_db do |db|
      db.execute("SELECT * FROM uute_objects WHERE category = 'gspo'")
    end

    added = 0
    skipped = 0
    reviewed = 0

    UuteDB.with_db do |db|
      contacts.each do |contact|
        reviewed += 1
        next unless UuteDB.links_for_contact(db, contact['id']).empty?

        best = uutes.map { |uute| match_contact_uute(contact, uute).merge(uute: uute) }.max_by { |m| m[:score] }
        if best && best[:score] >= 85
          UuteDB.create_or_update_link(
            db,
            uute_id: best[:uute]['id'],
            contact_id: contact['id'],
            status: 'auto',
            match_score: best[:score],
            match_reason: best[:reason]
          )
          added += 1
        else
          skipped += 1
        end
      end
    end

    { reviewed: reviewed, added: added, skipped: skipped }
  end

  def link_by_identifier!
    all_contact_ids = ContactsDB.with_db do |db|
      db.execute('SELECT id FROM contacts').map { |row| row['id'].to_i }
    end
    contacts = ContactsDB.with_db do |db|
      db.execute("SELECT * FROM contacts WHERE category = 'gspo' AND COALESCE(identifier, '') <> ''")
    end
    uutes = UuteDB.with_db do |db|
      db.execute("SELECT * FROM uute_objects WHERE category = 'gspo' AND COALESCE(identifier, '') <> ''")
    end

    uutes_by_identifier = uutes.group_by { |row| row['identifier'].to_s.strip.downcase }
    contacts_by_identifier = contacts.group_by { |row| row['identifier'].to_s.strip.downcase }
    duplicate_uute_identifiers = uutes_by_identifier.select { |identifier, rows| !identifier.empty? && rows.size > 1 }
    duplicate_contact_identifiers = contacts_by_identifier.select { |identifier, rows| !identifier.empty? && rows.size > 1 }

    linked = 0
    skipped_no_uute = 0
    skipped_duplicates = 0
    removed_stale_links = 0

    UuteDB.with_db do |db|
      removed_stale_links = cleanup_stale_contact_links(db, all_contact_ids)

      contacts.each do |contact|
        identifier = contact['identifier'].to_s.strip.downcase
        matches = uutes_by_identifier[identifier] || []
        if matches.empty?
          skipped_no_uute += 1
          next
        end
        if matches.size > 1 || contacts_by_identifier[identifier].to_a.size > 1
          skipped_duplicates += 1
          next
        end

        UuteDB.create_or_update_link(
          db,
          uute_id: matches.first['id'],
          contact_id: contact['id'],
          status: 'identifier',
          match_score: 100,
          match_reason: 'совпадение идентификатора'
        )
        linked += 1
      end
    end

    {
      contacts_with_identifier: contacts.size,
      uutes_with_identifier: uutes.size,
      linked: linked,
      skipped_no_uute: skipped_no_uute,
      skipped_duplicates: skipped_duplicates,
      removed_stale_links: removed_stale_links,
      duplicate_contact_identifiers: duplicate_contact_identifiers.keys,
      duplicate_uute_identifiers: duplicate_uute_identifiers.keys
    }
  end

  def import_file(path, filename: nil)
    book = Spreadsheet.open(path)
    sheet = book.worksheets.find { |ws| ws.name.to_s.include?('Гаражи') } || book.worksheets.first
    raise ArgumentError, 'Лист с данными не найден' unless sheet

    added = 0
    updated = 0
    unchanged = 0
    skipped = 0
    total = 0
    updated_examples = []

    UuteDB.with_db do |db|
      db.execute('BEGIN')
      begin
        header_map = resolved_columns(sheet)
        duplicate_identifiers = duplicate_identifiers(sheet, header_map)
        identifier_seen = Hash.new(0)
        (1...sheet.row_count).each do |row_index|
          total += 1
          attrs = attrs_from_row(sheet, row_index, header_map)
          if attrs.nil?
            skipped += 1
            next
          end
          identifier = attrs['identifier'].to_s.strip.downcase
          unless identifier.empty?
            identifier_seen[identifier] += 1
            if duplicate_identifiers.include?(identifier) && identifier_seen[identifier] > 1
              attrs['source_key'] = fallback_source_key(attrs)
            end
          end

          result = UuteDB.upsert_object(db, attrs)
          case result[:status]
          when :added
            added += 1
          when :updated
            updated += 1
            if updated_examples.size < 100
              updated_examples << {
                id: result[:id],
                source_row: attrs['source_row'],
                name: attrs['name'],
                address: attrs['address'],
                identifier: attrs['identifier'],
                changed_fields: result[:changed_fields],
                changes: result[:changes]
              }
            end
          else
            unchanged += 1
          end
        end
        UuteDB.record_import(db, filename: filename || File.basename(path), added: added, updated: updated, skipped: skipped, total: total)
        db.execute('COMMIT')
      rescue StandardError => e
        db.execute('ROLLBACK') rescue nil
        raise e
      end
    end

    {
      added: added,
      updated: updated,
      unchanged: unchanged,
      skipped: skipped,
      total: total,
      updated_examples: updated_examples
    }
  end

  def editable_fields
    ((XLS_COLUMNS.keys - %w[source_row name address identifier]) + %w[commercial_accounting]).uniq
  end

  def attrs_from_row(sheet, row_index, columns = nil)
    columns ||= resolved_columns(sheet)
    attrs = { 'category' => 'gspo' }
    XLS_COLUMNS.each_key do |key|
      col = columns[key]
      value = col.nil? ? '' : cell_value(sheet[row_index, col], key)
      attrs[key] = value
    end

    name = attrs['name'].to_s.strip
    address = attrs['address'].to_s.strip
    identifier = attrs['identifier'].to_s.strip
    return nil if name.empty? && address.empty? && identifier.empty?
    return nil if name.casecmp('Пусто').zero?

    attrs['source_row'] = row_index + 1
    computed_nearest = computed_nearest_verification(attrs)
    attrs['nearest_verification_date'] = computed_nearest unless computed_nearest.empty?
    attrs['source_key'] = source_key(attrs)
    attrs['periods_json'] = JSON.generate([])
    attrs['raw_json'] = JSON.generate(raw_row(sheet, row_index, columns))
    attrs
  end
  private_class_method :attrs_from_row

  def computed_nearest_verification(attrs)
    keys = %w[
      calculator_verification_date
      flowmeter_verification_date_1
      flowmeter_verification_date_2
      flowmeter_verification_date_3
      flowmeter_verification_date_4
      temp_sensor_verification_date_1
      temp_sensor_verification_date_2
      temp_sensor_verification_date_3
      temp_sensor_verification_date_4
      pressure_sensor_verification_date_1
      pressure_sensor_verification_date_2
      pressure_sensor_verification_date_3
      pressure_sensor_verification_date_4
    ]
    dates = keys.filter_map { |key| parse_ru_date(attrs[key]) }
    dates.min&.strftime('%d.%m.%Y').to_s
  end
  private_class_method :computed_nearest_verification

  def parse_ru_date(value)
    text = value.to_s.strip
    return nil if text.empty?

    Date.strptime(text, '%d.%m.%Y')
  rescue ArgumentError
    nil
  end
  private_class_method :parse_ru_date

  def source_key(attrs)
    identifier = attrs['identifier'].to_s.strip
    return "identifier:#{identifier.downcase}" unless identifier.empty?

    fallback_source_key(attrs)
  end
  private_class_method :source_key

  def fallback_source_key(attrs)
    contract = attrs['contract_number'].to_s.strip
    address = attrs['address'].to_s.strip.downcase
    name = attrs['name'].to_s.strip.downcase
    "fallback:#{contract}:#{address}:#{name}"
  end
  private_class_method :fallback_source_key

  def duplicate_identifiers(sheet, columns)
    counts = Hash.new(0)
    (1...sheet.row_count).each do |row_index|
      col = columns['identifier']
      next if col.nil?

      identifier = cell_value(sheet[row_index, col], 'identifier').to_s.strip.downcase
      counts[identifier] += 1 unless identifier.empty?
    end
    counts.select { |_, count| count > 1 }.keys
  end
  private_class_method :duplicate_identifiers

  def raw_row(sheet, row_index, columns = nil)
    columns ||= resolved_columns(sheet)
    columns.each_with_object({}) do |(key, col), memo|
      value = cell_value(sheet[row_index, col], key)
      memo[key] = value unless value.to_s.empty?
    end
  end
  private_class_method :raw_row

  def resolved_columns(sheet)
    headers = header_columns(sheet)
    XLS_COLUMNS.each_with_object({}) do |(key, fallback_col), memo|
      header, occurrence = XLS_HEADERS[key]
      memo[key] = headers[[normalize_header(header), occurrence]] || fallback_col
    end
  end
  private_class_method :resolved_columns

  def header_columns(sheet, row_index = 0)
    occurrences = Hash.new(0)
    (0...sheet.column_count).each_with_object({}) do |col, memo|
      header = normalize_header(cell_value(sheet[row_index, col]))
      next if header.empty?

      occurrences[header] += 1
      memo[[header, occurrences[header]]] = col
    end
  end
  private_class_method :header_columns

  def normalize_header(value)
    value.to_s.downcase.tr('ё', 'е').gsub(/\s+/, ' ').strip
  end
  private_class_method :normalize_header

  def cell_value(value, key = nil)
    value = value.value if value.respond_to?(:value)
    return '' if excel_error?(value)

    case value
    when Date
      value.strftime('%d.%m.%Y')
    when Time
      value.strftime('%d.%m.%Y')
    when Float
      return excel_serial_to_date(value) if date_field?(key) && value > 20_000

      value % 1 == 0 ? value.to_i.to_s : value.to_s
    when Integer
      return excel_serial_to_date(value) if date_field?(key) && value > 20_000

      value.to_s
    else
      text = value.to_s.strip
      excel_error_text?(text) ? '' : text
    end
  end
  private_class_method :cell_value

  def date_field?(key)
    return DATE_COLUMNS.include?(key.to_i) if key.to_s.match?(/\A\d+\z/)

    DATE_FIELDS.include?(key.to_s)
  end
  private_class_method :date_field?

  def excel_error?(value)
    value.class.name.include?('Spreadsheet::Excel::Error')
  end
  private_class_method :excel_error?

  def excel_error_text?(text)
    text.match?(/\A#<Spreadsheet::Excel::Error:/) || text.match?(/\A#(DIV\/0!|VALUE!|REF!|N\/A|NAME\?|NUM!|NULL!)/i)
  end
  private_class_method :excel_error_text?

  def excel_serial_to_date(value)
    (Date.new(1899, 12, 30) + value.to_i).strftime('%d.%m.%Y')
  end
  private_class_method :excel_serial_to_date

  def public_row(row, detail: false)
    result = row.each_with_object({}) { |(k, v), memo| memo[k.to_sym] = v }
    object_id = row['object_id'].to_i
    if object_id > 0
      object = ContactsDB.with_db { |db| ContactsDB.find_registry_object(db, object_id) }
      if object
        result[:name] = object['name'] unless object['name'].to_s.strip.empty?
        result[:address] = object['address'] unless object['address'].to_s.strip.empty?
        result[:identifier] = object['identifier'] unless object['identifier'].to_s.strip.empty?
      end
    end
    result[:periods] = parse_json(row['periods_json'])
    result[:extra_seals] = parse_extra_seals(row['extra_seals_json'])
    checks = parse_json(row['arshin_checks_json'])
    result[:arshin_checks] = checks.is_a?(Hash) ? checks : {}
    if detail
      result[:exploitation_period] = exploitation_period_label(
        row['date_input_uute'],
        row['date_output_uute']
      )
    end
    result[:raw] = parse_json(row['raw_json']) if detail
    result.delete(:periods_json)
    result.delete(:extra_seals_json)
    result.delete(:arshin_checks_json)
    result.delete(:raw_json) unless detail
    result
  end
  private_class_method :public_row

  def link_with_uute(link)
    uute = UuteDB.with_db { |db| UuteDB.find(db, link['uute_id']) }
    return nil unless uute

    { link: public_link(link), uute: public_row(uute) }
  end
  private_class_method :link_with_uute

  def link_with_contact(link)
    contact = ContactsDB.with_db { |db| ContactsDB.find_by_id(db, link['contact_id']) }
    return nil unless contact

    { link: public_link(link), contact: contact }
  end
  private_class_method :link_with_contact

  def cleanup_stale_contact_links(db, valid_contact_ids)
    valid_ids = valid_contact_ids.map(&:to_i).to_h { |id| [id, true] }
    stale_ids = db.execute('SELECT id, contact_id FROM uute_contact_links').filter_map do |row|
      row['id'].to_i unless valid_ids[row['contact_id'].to_i]
    end
    stale_ids.each { |id| db.execute('DELETE FROM uute_contact_links WHERE id = ?', [id]) }
    stale_ids.size
  end
  private_class_method :cleanup_stale_contact_links

  def public_link(link)
    {
      id: link['id'].to_i,
      uute_id: link['uute_id'].to_i,
      contact_id: link['contact_id'].to_i,
      status: link['status'],
      match_score: link['match_score'],
      match_reason: link['match_reason']
    }
  end
  private_class_method :public_link

  def uute_candidates_for_contact(contact, exclude_ids: [])
    UuteDB.with_db do |db|
      db.execute("SELECT * FROM uute_objects WHERE category = 'gspo'")
    end
      .reject { |uute| exclude_ids.include?(uute['id'].to_i) }
      .map { |uute| match_contact_uute(contact, uute).merge(uute: public_row(uute)) }
      .select { |item| item[:score] >= 25 }
      .sort_by { |item| -item[:score] }
      .first(10)
  end
  private_class_method :uute_candidates_for_contact

  def contact_candidates_for_uute(uute, exclude_ids: [])
    ContactsDB.with_db do |db|
      db.execute("SELECT * FROM contacts WHERE category = 'gspo'")
    end
      .reject { |contact| exclude_ids.include?(contact['id'].to_i) }
      .map { |contact| match_contact_uute(contact, uute).merge(contact: contact) }
      .select { |item| item[:score] >= 25 }
      .sort_by { |item| -item[:score] }
      .first(10)
  end
  private_class_method :contact_candidates_for_uute

  def match_contact_uute(contact, uute)
    contact_identifier = contact['identifier'].to_s.strip.downcase
    uute_identifier = uute['identifier'].to_s.strip.downcase
    if !contact_identifier.empty? && contact_identifier == uute_identifier
      return { score: 100, reason: 'идентификатор' }
    end

    contact_name = normalize_name(contact['name'])
    uute_name = normalize_name(uute['name'])
    contact_address = normalize_address(contact['address'])
    uute_address = normalize_address(uute['address'])
    contact_person = normalize_text(contact['consumer'])
    service_org = normalize_text(uute['service_org'])

    score = 0
    reasons = []

    if !contact_name.empty? && contact_name == uute_name
      score += 55
      reasons << 'название'
    elsif token_overlap(contact_name, uute_name) >= 0.7
      score += 35
      reasons << 'похоже название'
    elsif contains_token_name?(contact_name, uute_name)
      score += 25
      reasons << 'часть названия'
    end

    if !contact_address.empty? && contact_address == uute_address
      score += 45
      reasons << 'адрес'
    elsif address_close?(contact_address, uute_address)
      score += 25
      reasons << 'похож адрес'
    end

    if !contact_person.empty? && !service_org.empty? && token_overlap(contact_person, service_org) >= 0.5
      score += 10
      reasons << 'ответственный'
    end

    { score: [score, 100].min, reason: reasons.join(', ') }
  end
  private_class_method :match_contact_uute

  def normalize_name(value)
    normalize_text(value)
      .gsub(/\bгспо\b/, ' ')
      .gsub(/\bигб\b/, ' ')
      .gsub(/\bкооператив\b/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end
  private_class_method :normalize_name

  def normalize_address(value)
    normalize_text(value)
      .gsub(/\bул\b/, ' ')
      .gsub(/\bстр\b/, ' ')
      .gsub(/\bстроение\b/, ' ')
      .gsub(/\bпр\b/, ' ')
      .gsub(/\bпроезд\b/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end
  private_class_method :normalize_address

  def normalize_text(value)
    value.to_s
      .downcase
      .tr('ё', 'е')
      .gsub(/[«»"№.,()\/\\_-]+/, ' ')
      .gsub(/\s+/, ' ')
      .strip
  end
  private_class_method :normalize_text

  def token_overlap(left, right)
    a = left.split(/\s+/).reject { |t| t.length < 2 }
    b = right.split(/\s+/).reject { |t| t.length < 2 }
    return 0.0 if a.empty? || b.empty?

    (a & b).size.to_f / [a.size, b.size].max
  end
  private_class_method :token_overlap

  def contains_token_name?(left, right)
    return false if left.empty? || right.empty?

    left.include?(right) || right.include?(left)
  end
  private_class_method :contains_token_name?

  def address_close?(left, right)
    return false if left.empty? || right.empty?

    token_overlap(left, right) >= 0.55 || left.include?(right) || right.include?(left)
  end
  private_class_method :address_close?

  def parse_json(value)
    JSON.parse(value.to_s)
  rescue JSON::ParserError, TypeError
    []
  end
  private_class_method :parse_json
end
