#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/scp'
require 'net/ssh'

host = ENV.fetch('DEPLOY_HOST')
user = ENV.fetch('DEPLOY_USER', 'root')
password = ENV.fetch('DEPLOY_PASSWORD')
local = ENV.fetch('DEPLOY_LOCAL', File.expand_path('../migrate-pack.zip', __dir__))
remote = ENV.fetch('DEPLOY_REMOTE', '/root/migrate-pack.zip')

abort "Missing file: #{local}" unless File.file?(local)

Net::SSH.start(host, user, password: password, non_interactive: true, verify_host_key: :never) do |ssh|
  ssh.scp.upload!(local, remote)
  puts "Uploaded #{local} -> #{host}:#{remote} (#{File.size(local)} bytes)"
end
