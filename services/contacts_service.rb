# frozen_string_literal: true

require 'fileutils'
require 'spreadsheet'

require_relative '../storage/contacts_db'

module ContactsService
  module_function

  PAGE_SIZE = 100
  SEARCH_LIMIT = 100
  EXPORT_DIR = File.expand_path('../cache/exports', __dir__)
  EXPORT_COLUMNS_BY_CATEGORY = {
    'uk_tsj' => [
      ['Название', 'name'],
      ['Адрес', 'address'],
      ['Руководитель', 'manager'],
      ['Телефон', 'phone'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ],
    'gspo' => [
      ['Точка присоединения', 'connection_point'],
      ['Название', 'name'],
      ['Адрес', 'address'],
      ['Потребитель', 'consumer'],
      ['Телефон', 'phone'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Наличие ПУ', 'metering_presence'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ],
    'phys' => [
      ['Потребитель', 'consumer'],
      ['Адрес', 'address'],
      ['Ф.И.О. руководителя', 'manager'],
      ['Телефон', 'phone'],
      ['Доп. телефон', 'phone_alt'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Ответственные лица', 'notes'],
      ['Обновлено', 'updated_at']
    ],
    'legal' => [
      ['Название', 'name'],
      ['Адрес', 'address'],
      ['Ф.И.О. руководителя', 'manager'],
      ['Ответственные лица', 'notes'],
      ['Телефон', 'phone'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ],
    'budget' => [
      ['Название', 'name'],
      ['Адрес', 'address'],
      ['Руководитель', 'manager'],
      ['Телефон', 'phone'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ],
    'iglakovo' => [
      ['Название', 'name'],
      ['Адрес', 'address'],
      ['Телефон для уведомлений', 'phone'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ],
    'embedded' => [
      ['Наименование', 'name'],
      ['Ф.И.О. руководителя', 'manager'],
      ['Адрес помещения', 'address'],
      ['Ответственные лица', 'notes'],
      ['Телефон', 'phone'],
      ['Email', 'email'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ],
    'bu2' => [
      ['Наименование', 'name'],
      ['Ф.И.О. руководителя', 'manager'],
      ['Адрес', 'address'],
      ['Ответственные лица', 'notes'],
      ['Наличие ПУ', 'metering_presence'],
      ['Почтовый адрес', 'postal_address'],
      ['Идентификатор', 'identifier'],
      ['Обновлено', 'updated_at']
    ]
  }.freeze

  def enabled?
    ContactsDB.with_db do |db|
      db.get_first_row('SELECT 1 FROM contacts LIMIT 1')
    end
    true
  rescue StandardError
    false
  end

  def categories
    ContactsDB.with_db { |db| ContactsDB.category_keys(db) }
  rescue StandardError
    ContactsDB::CATEGORIES
  end

  def category_records
    ContactsDB.with_db { |db| ContactsDB.categories(db) }
  end

  def category_label(category)
    key = category.to_s
    ContactsDB.with_db do |db|
      row = ContactsDB.category_by_key(db, key)
      return row['label'].to_s if row && !row['label'].to_s.strip.empty?
    end
    ContactsDB::CATEGORY_LABELS[key] || key
  rescue StandardError
    ContactsDB::CATEGORY_LABELS[category.to_s] || category.to_s
  end

  def category_exists?(category)
    ContactsDB.with_db { |db| ContactsDB.category_exists?(db, category) }
  end

  def create_category(attrs)
    label = attrs['label'].to_s.strip
    key = attrs['key'].to_s.strip
    key = slug_for_category(label) if key.empty?
    sort_order = attrs.key?('sort_order') ? attrs['sort_order'] : nil
    ContactsDB.with_db { |db| ContactsDB.create_category(db, key: key, label: label, sort_order: sort_order) }
  end

  def update_category(key, attrs)
    ContactsDB.with_db { |db| ContactsDB.update_category(db, key, attrs) }
  end

  def delete_category(key)
    ContactsDB.with_db { |db| ContactsDB.delete_category(db, key) }
  end

  def counts
    ContactsDB.with_db { |db| ContactsDB.count_by_category(db) }
  rescue StandardError
    {}
  end

  def last_sync_at
    ContactsDB.with_db { |db| ContactsDB.get_meta(db, 'last_sync_at')&.to_i }
  rescue StandardError
    nil
  end

  def list(category, page:, query: nil, page_size: PAGE_SIZE)
    size = page_size.to_i.positive? ? page_size.to_i : PAGE_SIZE
    offset = page.to_i * size
    q = query.to_s.strip
    ContactsDB.with_db do |db|
      if q.empty?
        total = ContactsDB.count_in_category(db, category)
        rows = ContactsDB.list_by_category(db, category, limit: size, offset: offset)
      else
        total = ContactsDB.count_search_in_category(db, category, q)
        rows = ContactsDB.search_by_category(db, category, q, limit: size, offset: offset)
      end
      [rows.map { |row| with_registry_object(row) }, total]
    end
  end

  def find(id)
    ContactsDB.with_db do |db|
      row = ContactsDB.find_by_id(db, id)
      row && with_registry_object(row, db: db)
    end
  end

  def create(category, attrs)
    ContactsDB.with_db { |db| with_registry_object(ContactsDB.create(db, category, attrs), db: db) }
  end

  def update(id, attrs)
    ContactsDB.with_db do |db|
      existing = ContactsDB.find_by_id(db, id)
      raise ArgumentError, 'contact not found' unless existing

      if existing['category'].to_s == 'gspo'
        forbidden = %w[name address identifier].select { |key| attrs.key?(key) || attrs.key?(key.to_sym) }
        unless forbidden.empty?
          raise ArgumentError, 'Для ГСПО поля name/address/identifier редактируются только через карточку объекта (registry_object).'
        end
      end

      with_registry_object(ContactsDB.update_by_id(db, id, attrs), db: db)
    end
  end

  def delete(id)
    ContactsDB.with_db { |db| ContactsDB.delete_by_id(db, id) }
  end

  def export_category(category)
    records = ContactsDB.with_db { |db| ContactsDB.all_by_category(db, category) }
    FileUtils.mkdir_p(EXPORT_DIR)

    filename = "contacts_#{category}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.xls"
    path = File.join(EXPORT_DIR, filename)

    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: category_label(category)[0, 31])
    header_format = Spreadsheet::Format.new(weight: :bold)

    columns = export_columns(category)

    columns.each_with_index do |(label, _key), col|
      sheet[0, col] = label
      sheet.row(0).set_format(col, header_format)
      sheet.column(col).width = [label.length + 4, 16].max
    end

    records.each_with_index do |record, row_index|
      row = row_index + 1
      columns.each_with_index do |(_label, key), col|
        sheet[row, col] = export_value(record, key)
      end
    end

    book.write(path)
    [path, filename]
  end

  def search(query)
    q = query.to_s.strip
    return [] if q.empty?

    ContactsDB.with_db { |db| ContactsDB.search(db, q, limit: SEARCH_LIMIT).map { |row| with_registry_object(row, db: db) } }
  end

  def with_registry_object(row, db: nil)
    return row unless row.is_a?(Hash)
    object_id = row['object_id'].to_i
    return row if object_id <= 0

    object = if db
               ContactsDB.find_registry_object(db, object_id)
             else
               ContactsDB.with_db { |inner| ContactsDB.find_registry_object(inner, object_id) }
             end
    return row unless object

    merged = row.dup
    merged['name'] = object['name'] unless object['name'].to_s.strip.empty?
    merged['address'] = object['address'] unless object['address'].to_s.strip.empty?
    merged['identifier'] = object['identifier'] unless object['identifier'].to_s.strip.empty?
    merged
  end
  private_class_method :with_registry_object

  def short_label(record, fallback_index: nil)
    cat = record['category'].to_s
    parts = []
    case cat
    when 'gspo'
      parts << record['address'] if non_empty?(record['address'])
      parts << record['name'] if non_empty?(record['name'])
    when 'phys'
      parts << record['consumer'] if non_empty?(record['consumer'])
      parts << record['address'] if non_empty?(record['address'])
    when 'iglakovo'
      parts << record['name'] if non_empty?(record['name'])
      parts << record['address'] if non_empty?(record['address'])
    else
      parts << record['name'] if non_empty?(record['name'])
      parts << record['address'] if non_empty?(record['address'])
    end

    label = parts.reject { |p| p.to_s.strip.empty? }.join(' — ')
    label = "#{category_label(cat)} ##{record['id']}" if label.empty?
    label = "#{fallback_index + 1}. #{label}" if fallback_index
    label.length > 60 ? label[0, 57] + '...' : label
  end

  def detail_text(record)
    cat = record['category'].to_s
    lines = ["📞 #{category_label(cat)}"]
    lines << ''

    case cat
    when 'uk_tsj'
      add_line(lines, '🏢 Наименование', record['name'])
      add_line(lines, '📍 Адрес',         record['address'])
      add_line(lines, '👤 Руководитель',  record['manager'])
      add_line(lines, '📞 Телефон',       record['phone'])
      add_line(lines, '✉️ Email',         record['email'])
      add_line(lines, '📬 Почтовый адрес', record['postal_address'])
    when 'gspo'
      add_line(lines, '🔌 Точка присоединения', record['connection_point'])
      add_line(lines, '🏢 Наименование',         record['name'])
      add_line(lines, '📍 Адрес',                 record['address'])
      add_line(lines, '👤 Потребитель',           record['consumer'])
      add_line(lines, '📞 Телефон',               record['phone'])
      add_line(lines, '✉️ Email',                 record['email'])
      add_line(lines, '📬 Почтовый адрес',         record['postal_address'])
    when 'phys'
      add_line(lines, '👤 Потребитель',  record['consumer'])
      add_line(lines, '📍 Адрес',         record['address'])
      add_line(lines, '👤 Ф.И.О. руководителя', record['manager'])
      add_line(lines, '📞 Телефон',       record['phone'])
      add_line(lines, '📞 Доп. телефон',  record['phone_alt'])
      add_line(lines, '✉️ Email',         record['email'])
      add_line(lines, '📬 Почтовый адрес', record['postal_address'])
      add_line(lines, '👥 Ответственные лица', record['notes'])
    when 'legal'
      add_line(lines, '🏢 Наименование',  record['name'])
      add_line(lines, '📍 Место нахожд.', record['address'])
      add_line(lines, '👤 Ф.И.О. руководителя', record['manager'])
      add_line(lines, '👥 Ответственные лица', record['notes'])
      add_line(lines, '📞 Телефон',       record['phone'])
      add_line(lines, '✉️ Email',         record['email'])
      add_line(lines, '📬 Почтовый адрес', record['postal_address'])
    when 'budget'
      add_line(lines, '🏢 Наименование',  record['name'])
      add_line(lines, '📍 Адрес',         record['address'])
      add_line(lines, '👤 Руководитель',  record['manager'])
      add_line(lines, '📞 Телефон',       record['phone'])
      add_line(lines, '✉️ Email',         record['email'])
      add_line(lines, '📬 Почтовый адрес', record['postal_address'])
    when 'iglakovo'
      add_line(lines, '🏠 Название',        record['name'])
      add_line(lines, '📍 Адрес',           record['address'])
      add_line(lines, '📞 Для уведомлений', record['phone'])
      add_line(lines, '✉️ Email',           record['email'])
      add_line(lines, '📬 Почтовый адрес',   record['postal_address'])
      add_line(lines, '🆔 Идентификатор',   record['identifier'])
    when 'embedded'
      add_line(lines, '🏢 Наименование',        record['name'])
      add_line(lines, '👤 Ф.И.О. руководителя', record['manager'])
      add_line(lines, '📍 Адрес помещения',     record['address'])
      add_line(lines, '👥 Ответственные лица',  record['notes'])
      add_line(lines, '📞 Телефон',             record['phone'])
      add_line(lines, '✉️ Email',               record['email'])
      add_line(lines, '📬 Почтовый адрес',       record['postal_address'])
      add_line(lines, '🆔 Идентификатор',       record['identifier'])
    when 'bu2'
      add_line(lines, '🏢 Наименование',        record['name'])
      add_line(lines, '👤 Ф.И.О. руководителя', record['manager'])
      add_line(lines, '📍 Адрес',               record['address'])
      add_line(lines, '👥 Ответственные лица',  record['notes'])
      add_line(lines, '🔧 Наличие ПУ',          record['metering_presence'])
      add_line(lines, '📬 Почтовый адрес',       record['postal_address'])
      add_line(lines, '🆔 Идентификатор',       record['identifier'])
    end

    lines.join("\n")
  end

  def add_line(lines, label, value)
    v = value.to_s.strip
    return if v.empty?

    lines << "#{label}: #{v}"
  end
  private_class_method :add_line

  def non_empty?(value)
    !value.to_s.strip.empty?
  end
  private_class_method :non_empty?

  def export_value(record, key)
    value = record[key]
    return '' if value.nil?
    return Time.at(value.to_i).strftime('%Y-%m-%d %H:%M:%S') if key == 'updated_at' && value.to_i.positive?
    return category_label(value) if key == 'category'

    value
  end
  private_class_method :export_value

  def export_columns(category)
    EXPORT_COLUMNS_BY_CATEGORY.fetch(category.to_s) do
      [
        ['Название', 'name'],
        ['Потребитель', 'consumer'],
        ['Адрес', 'address'],
        ['Руководитель', 'manager'],
        ['Телефон', 'phone'],
        ['Доп. телефон', 'phone_alt'],
        ['Email', 'email'],
        ['Почтовый адрес', 'postal_address'],
        ['Идентификатор', 'identifier'],
        ['Примечание', 'notes'],
        ['Обновлено', 'updated_at']
      ]
    end
  end
  private_class_method :export_columns

  def slug_for_category(label)
    text = label.to_s.strip.downcase
    map = {
      'а' => 'a', 'б' => 'b', 'в' => 'v', 'г' => 'g', 'д' => 'd', 'е' => 'e', 'ё' => 'e',
      'ж' => 'zh', 'з' => 'z', 'и' => 'i', 'й' => 'y', 'к' => 'k', 'л' => 'l', 'м' => 'm',
      'н' => 'n', 'о' => 'o', 'п' => 'p', 'р' => 'r', 'с' => 's', 'т' => 't', 'у' => 'u',
      'ф' => 'f', 'х' => 'h', 'ц' => 'c', 'ч' => 'ch', 'ш' => 'sh', 'щ' => 'sch',
      'ы' => 'y', 'э' => 'e', 'ю' => 'yu', 'я' => 'ya', 'ь' => '', 'ъ' => ''
    }
    slug = text.chars.map { |ch| map.fetch(ch, ch) }.join
    slug = slug.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    slug.empty? ? "category_#{Time.now.to_i}" : slug
  end
  private_class_method :slug_for_category
end

