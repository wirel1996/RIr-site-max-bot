# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require 'time'

module ShortLinkService
  module_function

  FILE_PATH = File.expand_path('../storage/short_links.json', __dir__)
  @mutex = Mutex.new

  def create(target:, expires_at: nil)
    t = target.to_s.strip
    raise ArgumentError, 'target required' if t.empty?

    @mutex.synchronize do
      data = load_all_unlocked
      code = generate_code(data)
      data[code] = {
        'target' => t,
        'expires_at' => expires_at ? expires_at.to_i : nil,
        'created_at' => Time.now.to_i
      }
      save_all_unlocked(data)
      code
    end
  end

  def resolve(code)
    c = code.to_s.strip
    return nil if c.empty?

    @mutex.synchronize do
      data = load_all_unlocked
      entry = data[c]
      return nil unless entry.is_a?(Hash)

      exp = entry['expires_at'].to_i
      if exp > 0 && exp < Time.now.to_i
        data.delete(c)
        save_all_unlocked(data)
        return nil
      end

      entry['target'].to_s
    end
  end

  def cleanup!
    @mutex.synchronize do
      now = Time.now.to_i
      data = load_all_unlocked
      changed = false
      data.delete_if do |_code, entry|
        exp = entry.is_a?(Hash) ? entry['expires_at'].to_i : 0
        expired = exp > 0 && exp < now
        changed ||= expired
        expired
      end
      save_all_unlocked(data) if changed
    end
  end

  def generate_code(data)
    20.times do
      code = SecureRandom.urlsafe_base64(6).tr('-_', 'ab')
      return code unless data.key?(code)
    end
    SecureRandom.hex(8)
  end
  private_class_method :generate_code

  def load_all_unlocked
    return {} unless File.exist?(FILE_PATH)
    parsed = JSON.parse(File.read(FILE_PATH))
    parsed.is_a?(Hash) ? parsed : {}
  rescue StandardError
    {}
  end
  private_class_method :load_all_unlocked

  def save_all_unlocked(data)
    FileUtils.mkdir_p(File.dirname(FILE_PATH))
    tmp = "#{FILE_PATH}.tmp"
    File.write(tmp, JSON.pretty_generate(data))
    File.rename(tmp, FILE_PATH)
  end
  private_class_method :save_all_unlocked
end
