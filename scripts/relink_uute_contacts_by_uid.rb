# frozen_string_literal: true

require 'json'
require 'sqlite3'
require 'fileutils'

uute_db_path = 'C:/max_bot/storage/uute.db'
contacts_db_path = 'C:/max_bot/storage/contacts.db'
report_path = 'C:/max_bot/storage/relink_uid_report.json'

timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
backup_path = "C:/max_bot/storage/uute.db.bak-before-relink-#{timestamp}"
FileUtils.cp(uute_db_path, backup_path)

contacts_db = SQLite3::Database.new(contacts_db_path)
contacts_db.results_as_hash = true
uute_db = SQLite3::Database.new(uute_db_path)
uute_db.results_as_hash = true

norm = ->(v) { v.to_s.strip.downcase }

contact_rows = contacts_db.execute("SELECT id, name, consumer, identifier FROM contacts WHERE category='gspo'")
uute_rows = uute_db.execute('SELECT id, name, address, identifier FROM uute_objects')

contacts_by_uid = Hash.new { |h, k| h[k] = [] }
contact_rows.each do |r|
  uid = norm.call(r['identifier'])
  next if uid.empty?
  name = r['name'].to_s.strip.empty? ? r['consumer'].to_s : r['name'].to_s
  contacts_by_uid[uid] << { id: r['id'].to_i, name: name }
end

uute_by_uid = Hash.new { |h, k| h[k] = [] }
uute_rows.each do |r|
  uid = norm.call(r['identifier'])
  next if uid.empty?
  uute_by_uid[uid] << { id: r['id'].to_i, name: r['name'].to_s, address: r['address'].to_s }
end

existing_links = uute_db.get_first_value('SELECT COUNT(*) FROM uute_contact_links').to_i

uid_conflicts = []
uid_candidates = []

all_uids = (contacts_by_uid.keys | uute_by_uid.keys)
all_uids.each do |uid|
  c = contacts_by_uid[uid]
  u = uute_by_uid[uid]
  next if c.empty? || u.empty?
  if c.size == 1 && u.size == 1
    uid_candidates << { uid: uid, contact_id: c[0][:id], uute_id: u[0][:id] }
  else
    uid_conflicts << {
      uid: uid,
      contacts: c,
      uute: u
    }
  end
end

uute_db.transaction
uute_db.execute('DELETE FROM uute_contact_links')
now = Time.now.to_i
uid_candidates.each do |lnk|
  uute_db.execute(
    'INSERT INTO uute_contact_links(uute_id, contact_id, status, match_score, match_reason, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)',
    [lnk[:uute_id], lnk[:contact_id], 'uid', 100, 'uid exact', now, now]
  )
end
uute_db.commit

after_links = uute_db.get_first_value('SELECT COUNT(*) FROM uute_contact_links').to_i

report = {
  backup: backup_path,
  existing_links_before: existing_links,
  inserted_links: uid_candidates.size,
  links_after: after_links,
  uid_conflicts_count: uid_conflicts.size,
  uid_conflicts_sample: uid_conflicts.first(30),
  contacts_with_uid: contacts_by_uid.keys.size,
  uute_with_uid: uute_by_uid.keys.size
}

File.write(report_path, JSON.pretty_generate(report))
puts JSON.generate(report)
