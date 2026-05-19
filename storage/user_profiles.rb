# frozen_string_literal: true

require 'json'
require 'fileutils'

module UserProfiles
  module_function

  FILE = File.expand_path('../data/user_profiles.json', __dir__)

  @mutex = Mutex.new
  @profiles = nil

  def load
    @mutex.synchronize do
      return @profiles if @profiles

      if File.exist?(FILE)
        @profiles = JSON.parse(File.read(FILE, encoding: 'UTF-8')) rescue {}
      else
        @profiles = {}
      end
      @profiles
    end
  end

  def persist
    FileUtils.mkdir_p(File.dirname(FILE))
    File.write(FILE, JSON.generate(@profiles || {}), encoding: 'UTF-8')
  rescue => e
    puts "UserProfiles.persist error: #{e.class}: #{e.message}"
  end
  private_class_method :persist

  def name_for(user_id)
    load[user_id.to_s]&.dig('name')
  end

  def chat_id_for(user_id)
    load[user_id.to_s]&.dig('chat_id')
  end

  def set_name(user_id, name, chat_id: nil)
    @mutex.synchronize do
      @profiles ||= {}
      existing = @profiles[user_id.to_s] || {}
      @profiles[user_id.to_s] = existing.merge(
        'name' => name.to_s,
        'set_at' => Time.now.to_i
      )
      @profiles[user_id.to_s]['chat_id'] = chat_id.to_i if chat_id
      persist
    end
    name
  end

  def update_chat_id(user_id, chat_id)
    @mutex.synchronize do
      @profiles ||= {}
      return unless @profiles[user_id.to_s]

      @profiles[user_id.to_s]['chat_id'] = chat_id.to_i
      persist
    end
  end

  def clear(user_id)
    @mutex.synchronize do
      @profiles ||= {}
      @profiles.delete(user_id.to_s)
      persist
    end
  end

  def all
    load.dup
  end

  def each_user
    load.each do |uid, profile|
      yield(uid, profile) if profile.is_a?(Hash)
    end
  end
end
