# frozen_string_literal: true

require_relative '../storage/contacts_db'
require_relative '../storage/uute_db'
require_relative '../storage/water_registry_db'
require_relative '../storage/app_settings'

module ObjectsService
  module_function

  @switch_counter_mutex = Mutex.new

  def categories
    [
      { key: 'gspo', label: 'ГСПО' },
      { key: 'phys', label: 'Прочие ФЛ' }
    ]
  end

  def list(category, query: nil)
    q = query.to_s.strip.downcase
    ContactsDB.with_db do |db|
      rows = db.execute(
        "SELECT ro.* FROM registry_objects ro " \
        "WHERE ro.id IN (SELECT DISTINCT object_id FROM contacts WHERE category = ? AND object_id IS NOT NULL AND object_id > 0) " \
        "ORDER BY COALESCE(NULLIF(TRIM(ro.address), ''), ro.name, ''), ro.id",
        [category.to_s]
      )
      rows = rows.select do |row|
        next true if q.empty?
        [row['name'], row['address'], row['identifier']].any? { |v| v.to_s.downcase.include?(q) }
      end
      rows.map { |row| public_object(row) }
    end
  end

  def detail(id)
    object = ContactsDB.with_db { |db| ContactsDB.find_registry_object(db, id) }
    return nil unless object

    contacts = ContactsDB.with_db do |db|
      db.execute(
        "SELECT id, category, name, address, identifier FROM contacts WHERE object_id = ? ORDER BY category, COALESCE(NULLIF(TRIM(address), ''), name, ''), id",
        [id.to_i]
      )
    end
    uute = UuteDB.with_db do |db|
      db.execute(
        "SELECT id, category, name, address, identifier FROM uute_objects WHERE object_id = ? ORDER BY COALESCE(NULLIF(TRIM(address), ''), name, ''), id",
        [id.to_i]
      )
    end
    water = WaterRegistryDB.with_db do |db|
      db.execute(
        'SELECT id, gspo_name, standalone_address, identifier, third_party_disconnection, third_party_disconnection_note FROM water_registry_rows WHERE object_id = ? ORDER BY numeric_point(point_number), gspo_name, id',
        [id.to_i]
      )
    end
    switch_events = ContactsDB.with_db { |db| ContactsDB.switch_events_for_object(db, id) }

    {
      object: public_object(object),
      contacts: contacts.map { |r| { id: r['id'].to_i, category: r['category'], name: r['name'], address: r['address'], identifier: r['identifier'] } },
      uute: uute.map { |r| { id: r['id'].to_i, category: r['category'], name: r['name'], address: r['address'], identifier: r['identifier'] } },
      water: water.map do |r|
        {
          id: r['id'].to_i,
          gspo_name: r['gspo_name'],
          standalone_address: r['standalone_address'],
          identifier: r['identifier'],
          third_party_disconnection: r['third_party_disconnection'],
          third_party_disconnection_note: r['third_party_disconnection_note']
        }
      end,
      switch_events: switch_events.map { |r| public_switch_event(r) }
    }
  end

  def create_switch_event(object_id, attrs)
    object = ContactsDB.with_db { |db| ContactsDB.find_registry_object(db, object_id) }
    raise ArgumentError, 'object not found' unless object

    kind = attrs['kind'].to_s.strip
    raise ArgumentError, 'kind must be disconnect or connect' unless %w[disconnect connect].include?(kind)

    event_date = attrs['event_date'].to_s.strip
    raise ArgumentError, 'Дата обязательна' if event_date.empty?

    act_number = allocate_switch_act_number
    actor_name = attrs['actor_name'].to_s.strip
    place = kind == 'disconnect' ? attrs['place'].to_s.strip : ''
    seal_numbers = kind == 'disconnect' ? normalize_seal_numbers(attrs['seal_numbers']) : ''

    event = ContactsDB.with_db do |db|
      db.execute('BEGIN')
      begin
        row = ContactsDB.create_switch_event(
          db,
          object_id: object_id,
          kind: kind,
          act_number: act_number,
          event_date: event_date,
          place: place,
          seal_numbers: seal_numbers,
          actor_name: actor_name
        )
        ContactsDB.set_object_contacts_disconnected(
          db,
          object_id: object_id,
          disconnected: kind == 'disconnect' ? 'да' : 'нет',
          disconnected_date: event_date
        )
        db.execute('COMMIT')
        row
      rescue StandardError => e
        db.execute('ROLLBACK') rescue nil
        raise e
      end
    end

    sync_water_disconnection!(
      object_id,
      kind: kind,
      act_number: act_number,
      event_date: event_date,
      place: place,
      actor_name: actor_name,
      seal_numbers: seal_numbers
    )
    public_switch_event(event)
  end

  def resync_from_switch_events!(object_id = nil)
    object_ids =
      if object_id
        [object_id.to_i]
      else
        ContactsDB.with_db do |db|
          db.execute('SELECT DISTINCT object_id FROM object_switch_events').map { |r| r['object_id'].to_i }
        end
      end

    object_ids.each do |oid|
      resync_contacts_for_object!(oid)
      resync_water_for_object!(oid)
    end
    object_ids.size
  end

  def resync_water_from_switch_events!(object_id = nil)
    resync_from_switch_events!(object_id)
  end

  def switch_act_counter_info
    { next_number: switch_act_next_number }
  end

  def set_switch_act_counter(next_number)
    number = next_number.to_i
    raise ArgumentError, 'Номер акта должен быть больше 0' if number <= 0

    AppSettings.set('object_switch_act_next_number', number)
    switch_act_counter_info
  end

  def public_object(row)
    {
      id: row['id'].to_i,
      name: row['name'],
      address: row['address'],
      identifier: row['identifier']
    }
  end

  def public_switch_event(row)
    {
      id: row['id'].to_i,
      object_id: row['object_id'].to_i,
      kind: row['kind'],
      act_number: row['act_number'],
      event_date: row['event_date'],
      place: row['place'],
      seal_numbers: row['seal_numbers'].to_s.split("\n").map(&:strip).reject(&:empty?),
      actor_name: row['actor_name'],
      created_at: row['created_at'].to_i,
      updated_at: row['updated_at'].to_i
    }
  end
  private_class_method :public_switch_event

  def resync_contacts_for_object!(object_id)
    event = latest_switch_event_for_object(object_id)
    return 0 unless event

    ContactsDB.with_db do |db|
      ContactsDB.set_object_contacts_disconnected(
        db,
        object_id: object_id,
        disconnected: event['kind'] == 'disconnect' ? 'да' : 'нет',
        disconnected_date: event['event_date']
      )
    end
    1
  end

  def resync_water_for_object!(object_id)
    event = latest_switch_event_for_object(object_id)
    return 0 unless event

    sync_water_disconnection!(
      object_id,
      kind: event['kind'],
      act_number: event['act_number'],
      event_date: event['event_date'],
      place: event['place'],
      actor_name: event['actor_name'],
      seal_numbers: event['seal_numbers']
    )
    1
  end

  def latest_switch_event_for_object(object_id)
    ContactsDB.with_db do |db|
      db.get_first_row(
        "SELECT * FROM object_switch_events WHERE object_id = ? ORDER BY COALESCE(NULLIF(event_date, ''), created_at) DESC, id DESC LIMIT 1",
        [object_id.to_i]
      )
    end
  end
  private_class_method :latest_switch_event_for_object

  def sync_water_disconnection!(object_id, kind:, act_number:, event_date:, place:, actor_name:, seal_numbers: '')
    note = water_switch_note(kind: kind, act_number: act_number, event_date: event_date)

    WaterRegistryDB.with_db do |db|
      rows = db.execute('SELECT * FROM water_registry_rows WHERE object_id = ?', [object_id.to_i])
      rows.each do |row|
        attrs =
          if kind == 'disconnect'
            { 'third_party_disconnection_note' => note }
          else
            {
              'connection_act' => 'да',
              'connection_act_note' => note
            }
          end
        WaterRegistryDB.update(db, row['id'], attrs)
      end
    end
  end
  private_class_method :sync_water_disconnection!

  # Краткая строка для реестра «Вода на лето»: только статус, дата и № акта.
  def water_switch_note(kind:, act_number:, event_date:)
    parts = []
    parts << (kind == 'disconnect' ? 'Отключено' : 'Включено')
    parts << event_date.to_s.strip unless event_date.to_s.strip.empty?
    parts << "акт № #{act_number.to_s.strip}" unless act_number.to_s.strip.empty?
    parts.join(', ')
  end
  private_class_method :water_switch_note

  def normalize_seal_numbers(value)
    values =
      if value.is_a?(Array)
        value
      else
        value.to_s.split(/[\n,;]/)
      end
    values.map { |item| item.to_s.strip }.reject(&:empty?).join("\n")
  end
  private_class_method :normalize_seal_numbers

  def switch_act_next_number
    number = AppSettings.get('object_switch_act_next_number').to_i
    number.positive? ? number : 1
  end

  def allocate_switch_act_number
    @switch_counter_mutex.synchronize do
      number = switch_act_next_number
      AppSettings.set('object_switch_act_next_number', number + 1)
      number.to_s
    end
  end
  private_class_method :switch_act_next_number, :allocate_switch_act_number

  SWITCH_EXPORT_HEADERS = {
    'full' => [
      'Адрес',
      'UID',
      'Рег. № акта отключения',
      'Дата, кто отключал, пломбы',
      'Место отключения',
      'Рег. № акта включения',
      'Дата и кто включал'
    ],
    'disconnect' => [
      'Адрес',
      'UID',
      'Рег. № акта отключения',
      'Дата, кто отключал, пломбы',
      'Место отключения'
    ],
    'connect' => [
      'Адрес',
      'UID',
      'Рег. № акта включения',
      'Дата и кто включал'
    ]
  }.freeze

  def switch_events_export_rows(category, mode:)
    export_mode = SWITCH_EXPORT_HEADERS[mode.to_s] ? mode.to_s : 'full'
    headers = SWITCH_EXPORT_HEADERS[export_mode]

    ContactsDB.with_db do |db|
      objects = db.execute(
        "SELECT ro.* FROM registry_objects ro " \
        "WHERE ro.id IN (SELECT DISTINCT object_id FROM contacts WHERE category = ? AND object_id IS NOT NULL AND object_id > 0) " \
        "ORDER BY COALESCE(NULLIF(TRIM(ro.address), ''), ro.name, ''), ro.id",
        [category.to_s]
      )

      data_rows =
        objects.map do |obj|
          oid = obj['id'].to_i
          disconnect = ContactsDB.latest_switch_event(db, oid, kind: 'disconnect')
          connect = ContactsDB.latest_switch_event(db, oid, kind: 'connect')
          address = [obj['address'], obj['name']].map { |v| v.to_s.strip }.reject(&:empty?).join(', ')
          uid = obj['identifier'].to_s.strip

          case export_mode
          when 'disconnect'
            [
              address,
              uid,
              disconnect&.dig('act_number').to_s,
              switch_export_disconnect_details(disconnect),
              disconnect&.dig('place').to_s
            ]
          when 'connect'
            [
              address,
              uid,
              connect&.dig('act_number').to_s,
              switch_export_connect_details(connect)
            ]
          else
            [
              address,
              uid,
              disconnect&.dig('act_number').to_s,
              switch_export_disconnect_details(disconnect),
              disconnect&.dig('place').to_s,
              connect&.dig('act_number').to_s,
              switch_export_connect_details(connect)
            ]
          end
        end

      { headers: headers, rows: data_rows, mode: export_mode }
    end
  end

  def write_switch_events_export_xls(category, mode:)
    require 'spreadsheet'
    require 'tempfile'

    payload = switch_events_export_rows(category, mode: mode)
    Spreadsheet.client_encoding = 'UTF-8'
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: 'Объекты')
    bold = Spreadsheet::Format.new(weight: :bold, text_wrap: true)
    wrap = Spreadsheet::Format.new(text_wrap: true)

    payload[:headers].each_with_index do |header, col|
      sheet[0, col] = header
      sheet.row(0).set_format(col, bold)
    end

    payload[:rows].each_with_index do |row, row_index|
      row.each_with_index do |value, col|
        sheet[row_index + 1, col] = value.to_s
        sheet.row(row_index + 1).set_format(col, wrap) if col >= 2
      end
    end

    suffix =
      case payload[:mode]
      when 'disconnect' then 'отключения'
      when 'connect' then 'включения'
      else 'отключения_включения'
      end
    cat_label = category.to_s == 'gspo' ? 'ГСПО' : category.to_s.upcase
    filename = "Объекты_#{cat_label}_#{suffix}_#{Time.now.strftime('%Y%m%d')}.xls"
    tmpfile = Tempfile.new(['objects_switch_export', '.xls'])
    tmpfile.close
    book.write(tmpfile.path)
    [tmpfile.path, filename, payload[:rows].size]
  end

  def switch_export_disconnect_details(event)
    return '' unless event

    parts = []
    date = event['event_date'].to_s.strip
    parts << date unless date.empty?
    actor = event['actor_name'].to_s.strip
    parts << actor unless actor.empty?
    seals = event['seal_numbers'].to_s.split("\n").map(&:strip).reject(&:empty?)
    parts.concat(seals)
    parts.join(', ')
  end
  private_class_method :switch_export_disconnect_details

  def switch_export_connect_details(event)
    return '' unless event

    parts = []
    date = event['event_date'].to_s.strip
    parts << date unless date.empty?
    actor = event['actor_name'].to_s.strip
    parts << actor unless actor.empty?
    parts.join(', ')
  end
  private_class_method :switch_export_connect_details
end
