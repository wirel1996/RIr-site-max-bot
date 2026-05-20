# frozen_string_literal: true

require 'sqlite3'

db = SQLite3::Database.new('C:/max_bot/storage/contacts.db')
db.results_as_hash = true
cols = db.execute('PRAGMA table_info(contacts)').map { |r| r['name'] }
puts cols.join(',')
