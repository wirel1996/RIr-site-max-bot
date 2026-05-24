#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'

host = ENV.fetch('DEPLOY_HOST')
user = ENV.fetch('DEPLOY_USER', 'root')
password = ENV.fetch('DEPLOY_PASSWORD')
command = ARGV.join(' ')
abort 'Usage: ssh-run.rb <command>' if command.empty?

Net::SSH.start(host, user, password: password, non_interactive: true, verify_host_key: :never) do |ssh|
  ssh.exec!(command) do |_ch, stream, data|
    print data if data
  end
end
