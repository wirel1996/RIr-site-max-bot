# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'json'
require 'open3'

begin
  require 'prawn'
rescue LoadError
  # Prawn не установлен — будем использовать txt-фолбек.
end

module VerificationPdfService
  module_function

  STORAGE_DIR = File.expand_path('../storage/arshin_pdfs', __dir__)
  @prawn_load_error = nil

  def storage_dir
    FileUtils.mkdir_p(STORAGE_DIR)
    STORAGE_DIR
  end

  def prawn_available?
    ensure_prawn_loaded!
    defined?(Prawn) ? true : false
  end

  def ensure_prawn_loaded!
    return true if defined?(Prawn)

    require 'prawn'
    @prawn_load_error = nil
    true
  rescue LoadError => e
    @prawn_load_error = "#{e.class}: #{e.message}"
    false
  end

  def prawn_load_error
    @prawn_load_error.to_s
  end

  def font_path
    configured = ENV['PDF_FONT_PATH'].to_s.strip
    return configured if !configured.empty? && File.exist?(configured)

    [
      'C:/Windows/Fonts/arial.ttf',
      'C:/Windows/Fonts/calibri.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/TTF/DejaVuSans.ttf',
      '/usr/share/fonts/dejavu/DejaVuSans.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf'
    ].find { |p| File.exist?(p) }
  end

  def font_bold_path
    configured = ENV['PDF_FONT_BOLD_PATH'].to_s.strip
    return configured if !configured.empty? && File.exist?(configured)

    base = font_path.to_s
    return nil if base.empty?

    bold =
      case base
      when /arial\.ttf\z/i then base.sub(/arial\.ttf\z/i, 'arialbd.ttf')
      when /calibri\.ttf\z/i then base.sub(/calibri\.ttf\z/i, 'calibrib.ttf')
      when /DejaVuSans\.ttf\z/i then base.sub(/DejaVuSans\.ttf\z/i, 'DejaVuSans-Bold.ttf')
      else base
      end
    File.exist?(bold) ? bold : base
  end

  def enabled?
    prawn_available? && !font_path.nil?
  end

  def disabled_reason
    return "gem 'prawn' не загружен#{prawn_load_error.empty? ? '' : " (#{prawn_load_error})"}" unless prawn_available?
    return 'не найден шрифт для PDF (PDF_FONT_PATH)' if font_path.nil?

    'PDF генерация отключена'
  end

  def sanitize_filename(name)
    name.to_s.gsub(/[\\\/:\*\?"<>|]/, '_').strip
  end

  def out_path_for(name, ext)
    base = sanitize_filename(name).sub(/\.[A-Za-z0-9]+\z/, '')
    base = "verification_#{Time.now.to_i}_#{SecureRandom.hex(3)}" if base.empty?
    File.join(storage_dir, "#{base}.#{ext}").tr('\\', '/')
  end

  def field_pairs(item)
    pairs = []
    pairs << ['Заводской номер:', item[:serial]]
    pairs << ['Тип / обозначение:', item[:mit_notation]]
    pairs << ['Наименование:', item[:mit_title]]
    pairs << ['Поверитель:', item[:org_title]]
    pairs << ['Дата поверки:', item[:verification_date]]
    pairs << ['Действительна до:', item[:valid_date]]
    pairs << ['Документ:', item[:result_docnum]]
    pairs << ['Пригодность:', item[:applicability]]
    pairs << ['ID записи (vri_id):', item[:vri_id]]
    pairs.map { |k, v| [k, v.to_s.strip] }.reject { |_, v| v.empty? }
  end

  def generate(item, filename: nil)
    subproc_path, subproc_err = generate_via_subprocess(item, filename)
    return [subproc_path, nil] if subproc_path

    return txt_fallback(item, filename, reason: disabled_reason) unless enabled?

    out_path = out_path_for(filename, 'pdf')
    File.delete(out_path) if File.exist?(out_path)

    regular = font_path
    bold = font_bold_path

    Prawn::Document.generate(out_path, margin: 40) do |pdf|
      pdf.font_families.update('AppFont' => { normal: regular, bold: bold })
      pdf.font 'AppFont'

      pdf.font_size 18
      pdf.text 'Сведения о поверке средства измерений', styles: [:bold], align: :center
      pdf.move_down 8
      pdf.stroke_horizontal_rule
      pdf.move_down 14

      pdf.font_size 11
      field_pairs(item).each do |label, value|
        pdf.formatted_text(
          [
            { text: label + ' ', styles: [:bold] },
            { text: value }
          ],
          leading: 4
        )
        pdf.move_down 6
      end

      pdf.move_down 10
      registry_url = item[:registry_url].to_s.strip
      unless registry_url.empty?
        pdf.font_size 10
        pdf.formatted_text [
          { text: 'Источник: ', styles: [:bold] },
          { text: registry_url, link: registry_url, color: '0055AA' }
        ]
      end

      pdf.move_down 16
      pdf.font_size 8
      pdf.text(
        "Сгенерировано ботом #{Time.now.strftime('%d.%m.%Y %H:%M')} из данных АРШИН (ФГИС).",
        color: '888888'
      )
    end

    if File.exist?(out_path) && File.size(out_path) > 0
      # Проверяем что файл действительно PDF, а не мусор
      if out_path.end_with?('.pdf')
        header = File.open(out_path, 'rb') { |f| f.read(5) }
        unless header == '%PDF-'
          txt_fallback(item, filename, reason: 'Prawn создал невалидный PDF')
          return [out_path.sub(/\.pdf\z/i, '.txt'), nil]
        end
      end
      [out_path, nil]
    else
      txt_fallback(item, filename, reason: 'Prawn создал пустой файл')
    end
  rescue => e
    txt_fallback(item, filename, reason: "#{e.class}: #{e.message}")
  end

  def generate_via_subprocess(item, filename)
    script = File.expand_path('../scripts/generate_verification_pdf.rb', __dir__)
    return [nil, 'pdf script not found'] unless File.exist?(script)

    payload = JSON.generate(
      item: item.transform_keys(&:to_s),
      filename: filename.to_s
    )
    stdout, stderr, status = Open3.capture3('bundle', 'exec', 'ruby', script, stdin_data: payload)
    return [nil, "subprocess failed: #{stderr.to_s.strip}"] unless status.success?

    parsed = JSON.parse(stdout.to_s) rescue {}
    if parsed['ok'] == true && !parsed['path'].to_s.strip.empty? && File.exist?(parsed['path'].to_s)
      return [parsed['path'].to_s, nil]
    end
    [nil, parsed['error'].to_s.empty? ? 'subprocess unknown error' : parsed['error'].to_s]
  rescue => e
    [nil, "#{e.class}: #{e.message}"]
  end

  def txt_fallback(item, filename, reason: nil)
    out_path = out_path_for(filename, 'txt')

    lines = ['Сведения о поверке средства измерений', ('=' * 44)]
    field_pairs(item).each { |k, v| lines << "#{k} #{v}" }
    registry_url = item[:registry_url].to_s.strip
    lines << '' unless registry_url.empty?
    lines << "Источник: #{registry_url}" unless registry_url.empty?
    lines << ''
    lines << "Сгенерировано #{Time.now.strftime('%d.%m.%Y %H:%M')}"

    File.write(out_path, lines.join("\n"), encoding: 'UTF-8')
    [out_path, reason]
  end

  def cleanup_file(path)
    return if path.to_s.strip.empty?

    File.delete(path) if File.exist?(path)
  rescue => e
    warn "pdf cleanup error: #{e.class}: #{e.message}"
  end

  def cleanup_stale(max_age_seconds: 3600)
    return unless File.directory?(STORAGE_DIR)

    now = Time.now.to_i
    Dir.glob(File.join(STORAGE_DIR, '*.{pdf,txt}')).each do |f|
      File.delete(f) if (now - File.mtime(f).to_i) > max_age_seconds
    rescue StandardError
      next
    end
  end
end
