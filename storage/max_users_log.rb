# frozen_string_literal: true

require 'json'
require 'fileutils'

module MaxUsersLog
  module_function

  FILE = File.expand_path('../data/max_users.json', __dir__)

  @mutex = Mutex.new
  @users = nil

  def read_from_disk
    if File.exist?(FILE)
      JSON.parse(File.read(FILE, encoding: 'UTF-8')) rescue {}
    else
      {}
    end
  end
  private_class_method :read_from_disk

  def load
    @mutex.synchronize do
      @users ||= read_from_disk
      @users
    end
  end

  def persist
    FileUtils.mkdir_p(File.dirname(FILE))
    File.write(FILE, JSON.pretty_generate(@users || {}), encoding: 'UTF-8')
  rescue => e
    puts "MaxUsersLog.persist error: #{e.class}: #{e.message}"
  end
  private_class_method :persist

  def extract_sender(upd)
    update_type = upd['update_type'].to_s

    sender =
      if %w[user_added bot_started].include?(update_type)
        upd['user']
      elsif !upd.dig('callback', 'callback_id').to_s.empty?
        upd.dig('callback', 'user') || upd.dig('message', 'sender')
      else
        upd.dig('message', 'sender') || upd.dig('callback', 'user')
      end

    sender.is_a?(Hash) ? sender : nil
  end
  private_class_method :extract_sender

  def record(upd, chat_id: nil)
    sender = extract_sender(upd)
    return unless sender

    uid = sender['user_id']
    return if uid.nil? || uid.to_s.empty?

    key = uid.to_s

    @mutex.synchronize do
      @users ||= read_from_disk
      return if @users.key?(key)

      @users[key] = {
        'user_id' => uid.to_i,
        'first_name' => sender['first_name'].to_s,
        'last_name' => sender['last_name'].to_s,
        'name' => sender['name'].to_s,
        'is_bot' => sender['is_bot'] == true,
        'first_seen' => Time.now.to_i
      }
      @users[key]['chat_id'] = chat_id.to_i if chat_id

      persist
    end
  rescue => e
    puts "MaxUsersLog.record error: #{e.class}: #{e.message}"
  end

  def allowed?(user_id)
    load.dig(user_id.to_s, 'allowed') == true
  end

  def all
    load.dup
  end

  def clear_chat_id(user_id)
    key = user_id.to_s
    @mutex.synchronize do
      @users ||= read_from_disk
      return false unless @users.key?(key)

      @users[key].delete('chat_id')
      persist
      true
    end
  end

  def delete(user_id)
    key = user_id.to_s
    @mutex.synchronize do
      @users ||= read_from_disk
      return false unless @users.key?(key)

      @users.delete(key)
      persist
      true
    end
  end
end
