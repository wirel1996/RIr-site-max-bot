# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../storage/contacts_db'

path = ARGV[0] || File.expand_path('../tmp_bu2_info.json', __dir__)
raw = File.read(path, encoding: 'bom|utf-8')
rows = JSON.parse(raw)

attrs = rows.filter_map do |row|
  name = row['name'].to_s.strip
  manager = row['manager'].to_s.strip
  address = row['address'].to_s.strip
  identifier = row['identifier'].to_s.strip
  notes = row['notes'].to_s.strip
  metering_presence = row['metering_presence'].to_s.strip
  source_row = row['source_row'].to_i

  next if [name, manager, address, identifier, notes, metering_presence].all?(&:empty?)

  {
    name: name,
    connection_point: nil,
    consumer: nil,
    manager: manager,
    address: address,
    phone: nil,
    phone_alt: nil,
    email: nil,
    notes: notes,
    identifier: identifier,
    metering_presence: metering_presence,
    disconnected: nil,
    source_row: source_row
  }
end

backup = "#{ContactsDB.db_path}.bak-before-bu2-info-#{Time.now.strftime('%Y%m%d_%H%M%S')}"
FileUtils.cp(ContactsDB.db_path, backup) if File.exist?(ContactsDB.db_path)

ContactsDB.with_db do |db|
  ContactsDB.replace_category(db, 'bu2', attrs)
  ContactsDB.set_meta(db, 'last_bu2_contacts_import_at', Time.now.to_i.to_s)
end

ContactsDB.with_db do |db|
  total = ContactsDB.count_in_category(db, 'bu2')
  duplicate_uids = db.execute(<<~SQL)
    SELECT identifier, COUNT(*) AS c
    FROM contacts
    WHERE category = 'bu2' AND COALESCE(identifier, '') <> ''
    GROUP BY identifier
    HAVING COUNT(*) > 1
  SQL
  empty_uids = db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category = 'bu2' AND COALESCE(identifier, '') = ''").to_i

  puts "backup=#{backup}"
  puts "imported=#{attrs.size}"
  puts "total=#{total}"
  puts "empty_uids=#{empty_uids}"
  puts "duplicate_uid_groups=#{duplicate_uids.size}"
  duplicate_uids.each { |row| puts "#{row['identifier']}\t#{row['c']}" }
end
