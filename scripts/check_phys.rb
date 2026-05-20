require 'sqlite3'
db = SQLite3::Database.new('storage/contacts.db')
puts({total: db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category='phys'"), linked: db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category='phys' AND object_id>0"), with_uid: db.get_first_value("SELECT COUNT(*) FROM contacts WHERE category='phys' AND COALESCE(identifier,'')<>''")}.inspect)
