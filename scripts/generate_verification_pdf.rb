#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'

begin
  require 'bundler/setup'
rescue LoadError
  # continue
end

require 'prawn'

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

def font_bold_path(base)
  configured = ENV['PDF_FONT_BOLD_PATH'].to_s.strip
  return configured if !configured.empty? && File.exist?(configured)
  return nil if base.to_s.empty?

  bold =
    case base
    when /arial\.ttf\z/i then base.sub(/arial\.ttf\z/i, 'arialbd.ttf')
    when /calibri\.ttf\z/i then base.sub(/calibri\.ttf\z/i, 'calibrib.ttf')
    when /DejaVuSans\.ttf\z/i then base.sub(/DejaVuSans\.ttf\z/i, 'DejaVuSans-Bold.ttf')
    else base
    end
  File.exist?(bold) ? bold : base
end

def sanitize_filename(name)
  name.to_s.gsub(/[\\\/:\*\?"<>|]/, '_').strip
end

def out_path_for(name)
  dir = File.expand_path('../storage/arshin_pdfs', __dir__)
  FileUtils.mkdir_p(dir)
  base = sanitize_filename(name).sub(/\.[A-Za-z0-9]+\z/, '')
  base = "verification_#{Time.now.to_i}_#{SecureRandom.hex(3)}" if base.empty?
  File.join(dir, "#{base}.pdf").tr('\\', '/')
end

def field_pairs(item)
  pairs = []
  pairs << ['Заводской номер:', item['serial']]
  pairs << ['Тип / обозначение:', item['mit_notation']]
  pairs << ['Наименование:', item['mit_title']]
  pairs << ['Поверитель:', item['org_title']]
  pairs << ['Дата поверки:', item['verification_date']]
  pairs << ['Действительна до:', item['valid_date']]
  pairs << ['Документ:', item['result_docnum']]
  pairs << ['Пригодность:', item['applicability']]
  pairs << ['ID записи (vri_id):', item['vri_id']]
  pairs.map { |k, v| [k, v.to_s.strip] }.reject { |_, v| v.empty? }
end

begin
  input = JSON.parse(STDIN.read)
  item = input['item'] || {}
  filename = input['filename'].to_s

  regular = font_path
  raise 'font not found' if regular.to_s.empty?

  bold = font_bold_path(regular)
  out_path = out_path_for(filename)
  File.delete(out_path) if File.exist?(out_path)

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
      pdf.formatted_text([{ text: label + ' ', styles: [:bold] }, { text: value }], leading: 4)
      pdf.move_down 6
    end

    registry_url = item['registry_url'].to_s.strip
    unless registry_url.empty?
      pdf.move_down 10
      pdf.font_size 10
      pdf.formatted_text([{ text: 'Источник: ', styles: [:bold] }, { text: registry_url, link: registry_url, color: '0055AA' }])
    end
  end

  if File.exist?(out_path) && File.size(out_path) > 0 && File.open(out_path, 'rb') { |f| f.read(5) } == '%PDF-'
    puts JSON.generate(ok: true, path: out_path)
  else
    puts JSON.generate(ok: false, error: 'invalid pdf')
  end
rescue StandardError => e
  puts JSON.generate(ok: false, error: "#{e.class}: #{e.message}")
end

