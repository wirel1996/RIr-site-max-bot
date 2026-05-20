# frozen_string_literal: true

require_relative '../storage/contacts_db'

ContactsDB.with_db do |db|
  name = db.get_first_value("SELECT name FROM sqlite_master WHERE type='trigger' AND name='trg_contacts_identifier_immutable'")
  puts(name || 'MISSING')
end
