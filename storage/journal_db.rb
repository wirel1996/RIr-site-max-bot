# frozen_string_literal: true

require 'date'
require 'sqlite3'
require 'fileutils'

module JournalDB
  module_function

  @db_mutex = Mutex.new

  def db_path
    raw = ENV['JOURNAL_DB_PATH'].to_s.strip
    raw = './storage/journal.db' if raw.empty?
    File.expand_path(raw, File.dirname(__dir__))
  end

  def with_db
    @db_mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(db_path))
      db = SQLite3::Database.new(db_path)
      db.busy_timeout = 5_000
      db.execute('PRAGMA journal_mode = WAL')
      db.results_as_hash = true
      ensure_schema(db)
      begin
        yield db
      ensure
        db.close
      end
    end
  end

  def ensure_schema(db)
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS journal_cells (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        week_start TEXT NOT NULL,
        date_iso TEXT NOT NULL,
        weekday TEXT,
        time_slot TEXT NOT NULL,
        person TEXT NOT NULL,
        value TEXT,
        sheet TEXT,
        color TEXT,
        updated_at INTEGER NOT NULL,
        UNIQUE(date_iso, time_slot, person)
      );
      CREATE INDEX IF NOT EXISTS idx_journal_week ON journal_cells(week_start);
      CREATE INDEX IF NOT EXISTS idx_journal_date ON journal_cells(date_iso);
      CREATE INDEX IF NOT EXISTS idx_journal_person ON journal_cells(person);

      CREATE TABLE IF NOT EXISTS journal_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      );

      CREATE TABLE IF NOT EXISTS journal_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        date_iso TEXT NOT NULL,
        time_slot TEXT NOT NULL,
        person TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_journal_events_created ON journal_events(created_at);
      CREATE INDEX IF NOT EXISTS idx_journal_events_person ON journal_events(person);

      CREATE TABLE IF NOT EXISTS journal_notify_deliveries (
        event_id INTEGER NOT NULL,
        chat_id INTEGER NOT NULL,
        delivered_at INTEGER NOT NULL,
        PRIMARY KEY (event_id, chat_id)
      );
    SQL

    add_column_unless_exists(db, 'journal_cells', 'color', 'TEXT')
  end

  def add_column_unless_exists(db, table, column, definition)
    columns = db.execute("PRAGMA table_info(#{table})").map { |row| row['name'].to_s }
    return if columns.include?(column.to_s)

    db.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{definition}")
  end
  private_class_method :add_column_unless_exists

  def replace_week(db, week_start:, rows:)
    now = Time.now.to_i
    db.execute('BEGIN')
    begin
      db.execute('DELETE FROM journal_cells WHERE week_start = ?', [week_start])
      stmt = db.prepare(
        'INSERT INTO journal_cells(week_start, date_iso, weekday, time_slot, person, value, sheet, color, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)'
      )
      rows.each do |r|
        stmt.execute(
          week_start,
          r[:date_iso],
          r[:weekday].to_s,
          r[:time_slot],
          r[:person],
          r[:value].to_s,
          r[:sheet].to_s,
          r[:color].to_s,
          now
        )
      end
      stmt.close
      db.execute('COMMIT')
    rescue StandardError => e
      db.execute('ROLLBACK') rescue nil
      raise e
    end
  end

  def set_meta(db, key, value)
    db.execute(
      'INSERT INTO journal_meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key.to_s, value.to_s]
    )
  end

  def get_meta(db, key)
    row = db.get_first_row('SELECT value FROM journal_meta WHERE key = ?', [key.to_s])
    row && row['value']
  end

  def week_rows(db, week_start)
    db.execute(
      'SELECT * FROM journal_cells WHERE week_start = ? ORDER BY date_iso, time_slot, person',
      [week_start]
    )
  end

  def week_colors(db, week_start)
    db.execute(
      'SELECT date_iso, time_slot, person, color FROM journal_cells WHERE week_start = ? AND color IS NOT NULL AND color != \'\'',
      [week_start]
    )
  end

  def week_starts(db)
    db.execute('SELECT DISTINCT week_start FROM journal_cells ORDER BY week_start').map { |r| r['week_start'] }
  end

  def week_status(db, week_start)
    ws = week_start.to_s
    cells_revision = db.get_first_value(
      'SELECT COALESCE(MAX(updated_at), 0) FROM journal_cells WHERE week_start = ?',
      [ws]
    ).to_i
    monday = Date.iso8601(ws)
    week_end = (monday + 6).iso8601
    latest_event_id = db.get_first_value(
      'SELECT COALESCE(MAX(id), 0) FROM journal_events WHERE date_iso >= ? AND date_iso <= ?',
      [ws, week_end]
    ).to_i
    {
      'week_start' => ws,
      'cells_revision' => cells_revision,
      'latest_event_id' => latest_event_id
    }
  end

  def search(db, query, limit:)
    base = query.to_s.strip
    return [] if base.empty?
    db.execute(
      "SELECT week_start, date_iso, time_slot, person, value FROM journal_cells " \
      'ORDER BY date_iso DESC, time_slot DESC'
    )
  end

  def get_cell(db, date_iso:, time_slot:, person:)
    row = db.get_first_row(
      'SELECT value FROM journal_cells WHERE date_iso = ? AND time_slot = ? AND person = ?',
      [date_iso.to_s, time_slot.to_s, person.to_s]
    )
    row ? row['value'].to_s : nil
  end

  def upsert_cell(db, attrs)
    now = Time.now.to_i
    db.execute(
      'INSERT INTO journal_cells(week_start, date_iso, weekday, time_slot, person, value, sheet, color, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?) ' \
      'ON CONFLICT(date_iso, time_slot, person) DO UPDATE SET ' \
      'week_start=excluded.week_start, weekday=excluded.weekday, value=excluded.value, sheet=excluded.sheet, color=excluded.color, updated_at=excluded.updated_at',
      [
        attrs[:week_start].to_s,
        attrs[:date_iso].to_s,
        attrs[:weekday].to_s,
        attrs[:time_slot].to_s,
        attrs[:person].to_s,
        attrs[:value].to_s,
        attrs[:sheet].to_s,
        attrs[:color].to_s,
        now
      ]
    )
  end

  def upsert_cell_color(db, week_start:, date_iso:, time_slot:, person:, color:)
    now = Time.now.to_i
    db.execute(
      'INSERT INTO journal_cells(week_start, date_iso, time_slot, person, color, updated_at) VALUES(?, ?, ?, ?, ?, ?) ' \
      'ON CONFLICT(date_iso, time_slot, person) DO UPDATE SET color=excluded.color, updated_at=excluded.updated_at',
      [week_start.to_s, date_iso.to_s, time_slot.to_s, person.to_s, color.to_s, now]
    )
  end

  def week_colors(db, week_start)
    db.execute(
      'SELECT date_iso, time_slot, person, color FROM journal_cells WHERE week_start = ? AND color IS NOT NULL AND color != \'\'',
      [week_start]
    )
  end

  def cleanup_old_colors(db, older_than_iso)
    db.execute(
      'UPDATE journal_cells SET color = NULL WHERE week_start < ?',
      [older_than_iso]
    )
  end

  def add_event(db, date_iso:, time_slot:, person:, old_value:, new_value:)
    db.execute(
      'INSERT INTO journal_events(created_at, date_iso, time_slot, person, old_value, new_value) VALUES(?, ?, ?, ?, ?, ?)',
      [Time.now.to_i, date_iso.to_s, time_slot.to_s, person.to_s, old_value.to_s, new_value.to_s]
    )
  end

  def latest_event_id(db)
    row = db.get_first_row('SELECT MAX(id) AS id FROM journal_events')
    row && row['id'].to_i
  end

  def events_since(db, last_id, limit: 200)
    db.execute(
      'SELECT id, created_at, date_iso, time_slot, person, old_value, new_value FROM journal_events WHERE id > ? ORDER BY id ASC LIMIT ?',
      [last_id.to_i, limit.to_i]
    )
  end

  def notify_delivered?(db, event_id, chat_id)
    row = db.get_first_row(
      'SELECT 1 AS ok FROM journal_notify_deliveries WHERE event_id = ? AND chat_id = ?',
      [event_id.to_i, chat_id.to_i]
    )
    !row.nil?
  end

  def mark_notify_delivered(db, event_id, chat_id)
    db.execute(
      'INSERT OR IGNORE INTO journal_notify_deliveries(event_id, chat_id, delivered_at) VALUES(?, ?, ?)',
      [event_id.to_i, chat_id.to_i, Time.now.to_i]
    )
  end
end
