# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'open3'
require_relative '../storage/app_settings'
require_relative 'backup_mailer'

module DbBackupService
  module_function

  def backup_root
    File.expand_path('../storage/backups', __dir__)
  end

  def enabled?
    AppSettings.get('db_backup_enabled') == true
  end

  def email_to
    AppSettings.get('db_backup_email').to_s.strip
  end

  def daily_time
    raw = AppSettings.get('db_backup_daily_time').to_s.strip
    return '02:00' unless raw.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)

    raw
  end

  def database_files
    base = File.expand_path('../storage', __dir__)
    Dir.glob(File.join(base, '*.db')).select { |p| File.file?(p) }
  end

  def create_backup(now: Time.now.getlocal('+07:00'))
    files = database_files
    raise 'No .db files found' if files.empty?

    ts = now.strftime('%Y%m%d_%H%M%S')
    dir = File.join(backup_root, ts)
    FileUtils.mkdir_p(dir)
    copied = []
    files.each do |src|
      dst = File.join(dir, File.basename(src))
      FileUtils.cp(src, dst)
      copied << dst
    end

    zip_path = File.join(backup_root, "db-backup-#{ts}.zip")
    compress_to_zip(dir, zip_path)
    cleanup_old_backups!
    { ok: true, dir: dir, zip: zip_path, files: copied }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def send_email_report(result)
    return { ok: false, error: 'backup email disabled' } unless enabled?
    to = email_to
    return { ok: false, error: 'backup email is empty' } if to.empty?
    return { ok: false, error: 'mail not configured' } unless BackupMailer.configured?

    if result[:ok]
      BackupMailer.send_backup(
        email: to,
        subject: 'Ежедневный бэкап БД',
        text: "Бэкап успешно создан.\nФайл: #{result[:zip]}\nВремя: #{Time.now.strftime('%d.%m.%Y %H:%M:%S')}",
        attachment_path: result[:zip]
      )
    else
      BackupMailer.send_backup(
        email: to,
        subject: 'Ошибка бэкапа БД',
        text: "Бэкап не выполнен.\nОшибка: #{result[:error]}\nВремя: #{Time.now.strftime('%d.%m.%Y %H:%M:%S')}"
      )
    end
    { ok: true }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def cleanup_old_backups!(keep_days: 14)
    cutoff = Time.now - keep_days * 86_400
    Dir.glob(File.join(backup_root, '*')).each do |path|
      next unless File.exist?(path)
      next unless File.mtime(path) < cutoff

      FileUtils.rm_rf(path)
    end
  rescue StandardError
    nil
  end

  def compress_to_zip(source_dir, zip_path)
    ps = "Compress-Archive -Path '#{source_dir}\\*' -DestinationPath '#{zip_path}' -Force"
    stdout, stderr, status = Open3.capture3('powershell', '-NoProfile', '-Command', ps)
    return true if status.success?

    raise "Compress-Archive failed: #{stderr.to_s.strip.empty? ? stdout.to_s.strip : stderr.to_s.strip}"
  end
  private_class_method :compress_to_zip
end
