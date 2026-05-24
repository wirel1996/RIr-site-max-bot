# frozen_string_literal: true

require 'cgi'
require 'date'
require 'securerandom'
require 'tmpdir'
require 'zip'

require_relative 'water_registry_service'
require_relative '../storage/app_settings'

module WaterPhoneogramService
  module_function

  LAST_EXPORT_KEY = 'water_phoneogram_last_export'

  PROJECT_TEMPLATE_PATH = File.expand_path('../templates/water_phoneogram_template.docx', __dir__)
  TEMPLATE_PATH = ENV.fetch('WATER_PHONEOGRAM_TEMPLATE', PROJECT_TEMPLATE_PATH)

  SIGNERS = {
    'fadeev' => 'Фадеев Дмитрий Алексеевич',
    'ivanov' => 'Иванов Александр Николаевич',
    'ivanova' => 'Иванов Александр Николаевич',
    'golomansky' => 'Голоманский Владислав Витальевич',
    'barybin' => 'Барыбин Виктор Алексеевич'
  }.freeze

  def last_export
    raw = AppSettings.get(LAST_EXPORT_KEY)
    return nil unless raw.is_a?(Hash)

    payment_to = raw['payment_to'].to_s.strip
    return nil if payment_to.empty?

    {
      payment_from: raw['payment_from'].to_s,
      payment_to: payment_to,
      payment_to_ru: format_ru_date(payment_to),
      phoneogram_number: raw['phoneogram_number'].to_s.strip,
      document_date: raw['document_date'].to_s.strip,
      exported_at: raw['exported_at'].to_i
    }
  end

  def record_export!(payment_from:, payment_to:, phoneogram_number:, document_date:)
    AppSettings.set(
      LAST_EXPORT_KEY,
      {
        'payment_from' => payment_from.to_s,
        'payment_to' => payment_to.to_s,
        'phoneogram_number' => phoneogram_number.to_s.strip,
        'document_date' => document_date.to_s.strip,
        'exported_at' => Time.now.to_i
      }
    )
  end

  def build(payment_from: nil, payment_to: nil, signer: nil, phoneogram_number: nil, document_date: nil)
    raise ArgumentError, 'Шаблон телефонограммы не найден' unless File.exist?(TEMPLATE_PATH)

    data = WaterRegistryService.paid_rows(payment_from: payment_from, payment_to: payment_to)
    rows = data[:records]
    raise ArgumentError, 'За выбранный период оплаченных строк не найдено' if rows.empty?

    number = phoneogram_number.to_s.strip
    raise ArgumentError, 'Укажите номер телефонограммы' if number.empty?

    doc_date = resolve_document_date(document_date)
    date = Date.today
    filename = "Телефонограмма_ГСПО_#{date.strftime('%Y%m%d')}.docx"
    output_path = File.join(Dir.tmpdir, "#{SecureRandom.hex(8)}_#{filename}")
    signer_name = resolve_signer(signer)

    Zip::File.open(TEMPLATE_PATH) do |source_zip|
      Zip::File.open(output_path, create: true) do |target_zip|
        source_zip.each do |entry|
          content = entry.get_input_stream.read
          if entry.name == 'word/document.xml'
            content = patch_document_xml(
              content.force_encoding('UTF-8'),
              rows,
              doc_date,
              signer_name,
              phoneogram_number: number
            )
          end
          target_zip.get_output_stream(entry.name) { |stream| stream.write(content) }
        end
      end
    end

    record_export!(
      payment_from: data[:payment_from],
      payment_to: data[:payment_to],
      phoneogram_number: number,
      document_date: doc_date
    )

    [output_path, filename]
  end

  def patch_document_xml(xml, rows, header_date_ru, signer_name, phoneogram_number:)
    xml = xml.dup
    number = phoneogram_number.to_s.strip
    header = "Телефонограмма № #{number} от #{header_date_ru}"
    xml.sub!(/Телефонограмма №\s*.*?\s*от\s*\d{2}\.\d{2}\.\d{4}/, header)

    list_xml = rows.each_with_index.map do |row, index|
      point = row[:actual_connection_point].to_s.strip
      point = row[:point_number].to_s.strip if point.empty?
      name = row[:gspo_name].to_s.strip
      ending = index == rows.size - 1 ? '.' : ';'
      paragraph_xml("#{index + 1}.т. #{point} (#{name})#{ending}")
    end.join

    replaced = xml.sub!(
      /<w:p\b(?:(?!<\/w:p>).)*1\.т\.\s*184(?:(?!<\/w:p>).)*<\/w:p>\s*<w:p\b(?:(?!<\/w:p>).)*2\.т\.\s*103(?:(?!<\/w:p>).)*<\/w:p>/m,
      list_xml
    )
    return patch_signer(xml, signer_name) if replaced

    insert_before = xml.index(/<w:p\b(?:(?!<\/w:p>).)*Дату и время вызова представителя/m)
    raise ArgumentError, 'В шаблоне не найден блок со списком точек' unless insert_before

    xml.insert(insert_before, list_xml)
    patch_signer(xml, signer_name)
  end
  private_class_method :patch_document_xml

  def paragraph_xml(text)
    escaped = CGI.escapeHTML(text)
    <<~XML.delete("\n")
      <w:p>
        <w:pPr>
          <w:spacing w:after="0" w:line="240" w:lineRule="auto"/>
          <w:ind w:left="0"/>
          <w:jc w:val="both"/>
        </w:pPr>
        <w:r>
          <w:rPr>
            <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
            <w:sz w:val="28"/>
            <w:szCs w:val="28"/>
          </w:rPr>
          <w:t>#{escaped}</w:t>
        </w:r>
      </w:p>
    XML
  end
  private_class_method :paragraph_xml

  def resolve_signer(signer)
    key = signer.to_s.strip.downcase
    SIGNERS.fetch(key, SIGNERS['fadeev'])
  end
  private_class_method :resolve_signer

  def resolve_document_date(value)
    text = value.to_s.strip
    if (m = text.match(/\A(\d{1,2})\.(\d{1,2})\.(\d{4})\z/))
      return format('%02d.%02d.%04d', m[1].to_i, m[2].to_i, m[3].to_i)
    end
    if (d = Date.iso8601(text) rescue nil)
      return d.strftime('%d.%m.%Y')
    end

    Date.today.strftime('%d.%m.%Y')
  end
  private_class_method :resolve_document_date

  def format_ru_date(value)
    text = value.to_s.strip
    return text if text.match?(/\A\d{2}\.\d{2}\.\d{4}\z/)

    Date.iso8601(text).strftime('%d.%m.%Y')
  rescue ArgumentError, TypeError
    text
  end
  private_class_method :format_ru_date

  def patch_signer(xml, signer_name)
    escaped = CGI.escapeHTML(signer_name)
    result = xml.dup
    [
      'Фадеев Дмитрий Алексеевич',
      'Иванов Александр Николаевич',
      'Голоманский Владислав Витальевич',
      'Барыбин Виктор Алексеевич',
      'Фадеев Д.А.',
      'Иванов А.Н.',
      'Голоманский В.В.',
      'Барыбин В.А.',
      'Иванова А.С.',
      'Иванов А.С.'
    ].each do |name|
      result.gsub!(name, escaped)
    end

    result
      .gsub(/Фадеев\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+/u, escaped)
      .gsub(/Иванов\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+/u, escaped)
      .gsub(/Голоманский\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+/u, escaped)
      .gsub(/Барыбин\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+\s+[А-ЯЁа-яё]+/u, escaped)
      .gsub(/Фадеев\s+[А-ЯЁ]\.[А-ЯЁ]\./u, escaped)
      .gsub(/Иванов\s+[А-ЯЁ]\.[А-ЯЁ]\./u, escaped)
      .gsub(/Голоманский\s+[А-ЯЁ]\.[А-ЯЁ]\./u, escaped)
      .gsub(/Барыбин\s+[А-ЯЁ]\.[А-ЯЁ]\./u, escaped)
  end
  private_class_method :patch_signer
end
