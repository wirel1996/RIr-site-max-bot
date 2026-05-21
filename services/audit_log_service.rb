# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'spreadsheet'

require_relative '../storage/audit_log_db'

module AuditLogService
  module_function

  EXPORT_DIR = File.expand_path('../cache/exports', __dir__)
  DEFAULT_LIMIT = 200
  MAX_LIMIT = 1_000

  def record(actor:, action:, entity_type: nil, entity_id: nil, entity_label: nil, field: nil,
             old_value: nil, new_value: nil, details: nil, ip: nil, user_agent: nil)
    AuditLogDB.with_db do |db|
      AuditLogDB.insert(
        db,
        created_at: Time.now.to_i,
        actor_login: actor && actor[:login],
        actor_name: actor && actor[:name],
        action: action,
        entity_type: entity_type,
        entity_id: entity_id,
        entity_label: entity_label,
        field: field,
        old_value: old_value,
        new_value: new_value,
        details_json: details ? JSON.generate(details) : nil,
        ip: ip,
        user_agent: user_agent
      )
    end
  rescue StandardError => e
    warn "AuditLogService.record error: #{e.class}: #{e.message}"
  end

  def record_changes(actor:, action:, entity_type:, entity_id:, entity_label:, before:, after:, fields:, ip: nil, user_agent: nil)
    fields.each do |field|
      old_value = value_for(before, field)
      new_value = value_for(after, field)
      next if old_value == new_value

      record(
        actor: actor,
        action: action,
        entity_type: entity_type,
        entity_id: entity_id,
        entity_label: entity_label,
        field: field,
        old_value: old_value,
        new_value: new_value,
        ip: ip,
        user_agent: user_agent
      )
    end
  end

  def list(limit: DEFAULT_LIMIT, offset: 0, actor: nil, entity_type: nil, entity_id: nil, exclude_entity_type: nil, field: nil, action: nil)
    safe_limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    AuditLogDB.with_db do |db|
      AuditLogDB.list(
        db,
        limit: safe_limit,
        offset: offset.to_i,
        actor: actor,
        entity_type: entity_type,
        entity_id: entity_id,
        exclude_entity_type: exclude_entity_type,
        field: field,
        action: action
      ).map { |row| public_row(row) }
    end
  end

  def export_xls(entity_type: nil, exclude_entity_type: nil, filename_prefix: 'audit')
    rows = list(limit: MAX_LIMIT, entity_type: entity_type, exclude_entity_type: exclude_entity_type)
    FileUtils.mkdir_p(EXPORT_DIR)
    filename = "#{filename_prefix}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.xls"
    path = File.join(EXPORT_DIR, filename)

    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: 'Аудит')
    header_format = Spreadsheet::Format.new(weight: :bold)
    headers = ['Дата', 'Пользователь', 'Действие', 'Раздел', 'ID', 'Объект', 'Поле', 'Было', 'Стало', 'IP']
    headers.each_with_index do |header, col|
      sheet[0, col] = header
      sheet.row(0).set_format(col, header_format)
      sheet.column(col).width = [header.length + 4, 16].max
    end

    rows.each_with_index do |row, index|
      values = [
        Time.at(row[:created_at].to_i).strftime('%d.%m.%Y %H:%M:%S'),
        row[:actor_name].to_s.empty? ? row[:actor_login] : row[:actor_name],
        row[:action],
        row[:entity_type],
        row[:entity_id],
        row[:entity_label],
        row[:field],
        row[:old_value],
        row[:new_value],
        row[:ip]
      ]
      values.each_with_index { |value, col| sheet[index + 1, col] = value.to_s }
    end

    book.write(path)
    [path, filename]
  end

  def export_csv
    export_xls(exclude_entity_type: 'journal')
  end

  def export_journal_xls
    export_xls(entity_type: 'journal', filename_prefix: 'journal_audit')
  end

  def public_row(row)
    row.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
  end
  private_class_method :public_row

  def value_for(source, field)
    return '' unless source

    if source.respond_to?(:key?) && source.key?(field)
      source[field].to_s
    elsif source.respond_to?(:key?) && source.key?(field.to_sym)
      source[field.to_sym].to_s
    elsif source.respond_to?(:key?) && source.key?(field.to_s)
      source[field.to_s].to_s
    else
      ''
    end
  end
  private_class_method :value_for
end
