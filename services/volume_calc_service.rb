# frozen_string_literal: true

module VolumeCalcService
  module_function

  DEFAULTS = {
    'h' => nil,
    'v' => nil,
    'q' => nil,
    't_vn' => nil,
    'v_podval' => '0'
  }.freeze
  DIAPHRAGM_DEFAULTS = {
    'pressure_drop' => nil,
    'heating_load' => nil
  }.freeze

  T_N = -37.0
  ALPHA = 0.91

  def volume_form_normalize(form)
    normalized = DEFAULTS.dup
    (form || {}).each do |key, value|
      k = key.to_s
      next unless normalized.key?(k)

      text = value.to_s.strip
      normalized[k] = text.empty? ? nil : text
    end
    normalized
  end

  def diaphragm_form_normalize(form)
    normalized = DIAPHRAGM_DEFAULTS.dup
    (form || {}).each do |key, value|
      k = key.to_s
      next unless normalized.key?(k)

      text = value.to_s.strip
      normalized[k] = text.empty? ? nil : text
    end
    normalized
  end

  def max_volume_form_keyboard(form = {})
    f = volume_form_normalize(form)
    ArshinService.max_inline_keyboard([
      [{ text: "Н, м (высота): #{volume_form_value(f['h'])}", payload: 'volume:set:h' }],
      [{ text: "V, куб.м: #{volume_form_value(f['v'])}", payload: 'volume:set:v' }],
      [{ text: "q, ккал/куб.м·час·град: #{volume_form_value(f['q'])}", payload: 'volume:set:q' }],
      [{ text: "t, вн.: #{volume_form_value(f['t_vn'])}", payload: 'volume:set:t_vn' }],
      [{ text: "V подвал: #{volume_form_value(f['v_podval'])}", payload: 'volume:set:v_podval' }],
      [{ text: 'Рассчитать Qот', payload: 'volume:calc' }],
      [{ text: 'Очистить', payload: 'volume:clear' }],
      [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
    ])
  end

  def max_diaphragm_form_keyboard(form = {})
    f = diaphragm_form_normalize(form)
    ArshinService.max_inline_keyboard([
      [{ text: "Перепад давления: #{volume_form_value(f['pressure_drop'])}", payload: 'diaphragm:set:pressure_drop' }],
      [{ text: "Нагрузка на отопление: #{volume_form_value(f['heating_load'])}", payload: 'diaphragm:set:heating_load' }],
      [{ text: 'Рассчитать диафрагму', payload: 'diaphragm:calc' }],
      [{ text: 'Очистить', payload: 'diaphragm:clear' }],
      [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
    ])
  end

  def volume_calculate_by_form(form)
    f = volume_form_normalize(form)

    h = parse_number(f['h'])
    v = parse_number(f['v'])
    q = parse_number(f['q'])
    t_vn = parse_number(f['t_vn'])
    v_podval = parse_number(f['v_podval'])

    return 'Заполните поле Н, м (высота).' if h.nil?
    return 'Заполните поле V, куб.м.' if v.nil?
    return 'Заполните поле q, ккал/куб.м·час·град.' if q.nil?
    return 'Заполните поле t, вн.' if t_vn.nil?
    return 'Заполните поле V подвал.' if v_podval.nil?
    return 't, вн. не может быть -273 (деление на ноль в формуле).' if (273.0 + t_vn).abs < 1e-9

    root = Math.sqrt((1.0 - 234.0 / (273.0 + t_vn)) * 19.62 * h + 4.41)
    one_plus_ki = 1.0 + 0.01 * root

    q_ot = (v + (v_podval * 0.4)) * ALPHA * q * (t_vn - T_N) * one_plus_ki

    [
      "✅ Расчёт выполнен.",
      '',
      "Qот, ккал/час = #{format_number(q_ot, 4)}",
      '',
      "Использовано:",
      "• Н, м = #{format_number(h, 4)}",
      "• V, куб.м = #{format_number(v, 4)}",
      "• q, ккал/куб.м·час·град = #{format_number(q, 6)}",
      "• t, вн. = #{format_number(t_vn, 4)}",
      "• V подвал = #{format_number(v_podval, 4)}",
      "• tн = #{format_number(T_N, 1)}",
      "• α = #{format_number(ALPHA, 2)}",
      "• (1+Ки.р.) = #{format_number(one_plus_ki, 6)}"
    ].join("\n")
  rescue Math::DomainError
    'Не удалось посчитать: подкоренное выражение отрицательное. Проверьте Н и t, вн.'
  end

  def diaphragm_calculate_by_form(form)
    f = diaphragm_form_normalize(form)

    pressure_drop = parse_number(f['pressure_drop'])
    heating_load = parse_number(f['heating_load'])

    return 'Заполните поле Перепад давления.' if pressure_drop.nil?
    return 'Заполните поле Нагрузка на отопление.' if heating_load.nil?
    return 'Перепад давления должен быть больше 0.' if pressure_drop <= 0
    return 'Нагрузка на отопление должна быть больше 0.' if heating_load <= 0

    rounded = diaphragm_value(heating_load, pressure_drop)
    result = [rounded, 3.0].max
    washers =
      if rounded > 3.0
        '1 шайба'
      else
        two_washers = [diaphragm_value(heating_load, pressure_drop / 2.0), 3.0].max
        "2 шайбы по #{format_number(two_washers, 1)}"
      end

    [
      '✅ Расчёт выполнен.',
      '',
      "Дроссельная диафрагма = #{format_number(result, 1)}",
      "Вариант установки = #{washers}",
      '',
      'Использовано:',
      "• Перепад давления = #{format_number(pressure_drop, 4)}",
      "• Нагрузка на отопление = #{format_number(heating_load, 4)}"
    ].join("\n")
  end

  def volume_field_prompt(field)
    case field.to_s
    when 'h'
      "Введите Н, м (высота), например: 3.2\n'-' чтобы очистить поле"
    when 'v'
      "Введите (V) объем помещения, куб.м, например: 296.6\n'-' чтобы очистить поле"
    when 'q'
      "Введите q, ккал/куб.м·час·град, до 2000=0,7, от 2000 до 3000=0,6, от 3000=0,5\n'-' чтобы очистить поле"
    when 't_vn'
      "Введите t, внутреннюю температуру, например: 12\n'-' чтобы очистить поле"
    when 'v_podval'
      "Введите V подвал, объем подвала, например: 0\n'-' чтобы очистить поле"
    else
      "Введите значение.\n'-' чтобы очистить поле"
    end
  end

  def diaphragm_field_prompt(field)
    case field.to_s
    when 'pressure_drop'
      "Введите перепад давления, например: 0,12\n'-' чтобы очистить поле"
    when 'heating_load'
      "Введите нагрузку на отопление, например: 0,5\n'-' чтобы очистить поле"
    else
      "Введите значение.\n'-' чтобы очистить поле"
    end
  end

  def volume_form_value(value)
    text = value.to_s.strip
    text.empty? ? 'не задано' : text
  end
  private_class_method :volume_form_value

  def parse_number(value)
    text = value.to_s.strip
    return nil if text.empty?

    normalized = text.tr(',', '.').gsub(/\s+/, '')
    Float(normalized)
  rescue ArgumentError, TypeError
    nil
  end
  private_class_method :parse_number

  def diaphragm_value(excel_pressure, heating_load)
    raw = 10.0 * ((((excel_pressure * 1_000_000.0) / 80_000.0)**2 / heating_load)**0.25)
    (raw * 10.0).round / 10.0
  end
  private_class_method :diaphragm_value

  def format_number(value, precision = 4)
    format("%.#{precision}f", value.to_f).sub(/\.?0+\z/, '')
  end
  private_class_method :format_number
end
