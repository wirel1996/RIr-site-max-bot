# frozen_string_literal: true

require_relative '../storage/contacts_db'

module RegistryObjectsService
  module_function

  EDITABLE_FIELDS = %w[name address identifier].freeze

  def find(id)
    ContactsDB.with_db { |db| public_row(ContactsDB.find_registry_object(db, id)) }
  end

  def update(id, attrs)
    values = attrs.each_with_object({}) do |(key, value), memo|
      k = key.to_s
      next unless EDITABLE_FIELDS.include?(k)

      memo[k] = value.to_s.strip
    end
    raise ArgumentError, 'Нет полей объекта для обновления' if values.empty?
    raise ArgumentError, 'UID объекта нельзя очищать' if values.key?('identifier') && values['identifier'].empty?

    ContactsDB.with_db do |db|
      before = ContactsDB.find_registry_object(db, id)
      raise ArgumentError, 'object not found' unless before

      uid = values['identifier'].to_s.strip
      unless uid.empty? || uid.casecmp(before['identifier'].to_s.strip).zero?
        duplicate = ContactsDB.find_registry_object_by_identifier(db, uid)
        raise ArgumentError, 'Объект с таким UID уже существует' if duplicate && duplicate['id'].to_i != before['id'].to_i
      end

      after = ContactsDB.update_registry_object(db, id, values)
      [public_row(before), public_row(after)]
    end
  end

  def public_row(row)
    return nil unless row

    row.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
  end
  private_class_method :public_row
end
