# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

module AuditLogDB
  module_function

  @db_mutex = Mutex.new

  def db_path
    raw = ENV['AUDIT_LOG_DB_PATH'].to_s.strip
    raw = './storage/audit_log.db' if raw.empty?
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
      CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        actor_login TEXT,
        actor_name TEXT,
        action TEXT NOT NULL,
        entity_type TEXT,
        entity_id TEXT,
        entity_label TEXT,
        field TEXT,
        old_value TEXT,
        new_value TEXT,
        details_json TEXT,
        ip TEXT,
        user_agent TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_logs(actor_login);
      CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);
    SQL
  end

  def insert(db, attrs)
    db.execute(
      <<~SQL,
        INSERT INTO audit_logs (
          created_at, actor_login, actor_name, action, entity_type, entity_id,
          entity_label, field, old_value, new_value, details_json, ip, user_agent
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        attrs[:created_at].to_i,
        attrs[:actor_login].to_s,
        attrs[:actor_name].to_s,
        attrs[:action].to_s,
        attrs[:entity_type].to_s,
        attrs[:entity_id].to_s,
        attrs[:entity_label].to_s,
        attrs[:field].to_s,
        attrs[:old_value].to_s,
        attrs[:new_value].to_s,
        attrs[:details_json].to_s,
        attrs[:ip].to_s,
        attrs[:user_agent].to_s
      ]
    )
  end

  def list(db, limit:, offset: 0, actor: nil, entity_type: nil, entity_id: nil, exclude_entity_type: nil)
    clauses = []
    values = []
    unless actor.to_s.strip.empty?
      clauses << 'actor_login = ?'
      values << actor.to_s.strip
    end
    unless entity_type.to_s.strip.empty?
      clauses << 'entity_type = ?'
      values << entity_type.to_s.strip
    end
    unless entity_id.to_s.strip.empty?
      clauses << 'entity_id = ?'
      values << entity_id.to_s.strip
    end
    unless exclude_entity_type.to_s.strip.empty?
      clauses << 'entity_type <> ?'
      values << exclude_entity_type.to_s.strip
    end
    where = clauses.empty? ? '' : "WHERE #{clauses.join(' AND ')}"
    db.execute(
      "SELECT * FROM audit_logs #{where} ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?",
      values + [limit.to_i, offset.to_i]
    )
  end
end
