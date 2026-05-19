# frozen_string_literal: true

# CLI для управления пользователями сайта.
#
# Примеры:
#   ruby scripts/users_cli.rb list
#   ruby scripts/users_cli.rb add Балашов "Балашов А.А." mypassword
#   ruby scripts/users_cli.rb set-password Балашов newpass
#   ruby scripts/users_cli.rb delete Балашов

$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require_relative '../services/users_service'

cmd = ARGV.shift

case cmd
when 'list'
  users = UsersService.list
  if users.empty?
    puts '(пользователей нет — добавьте через add)'
  else
    users.each { |u| puts "  #{u[:login].ljust(20)} #{u[:name]}" }
  end

when 'add'
  login, name, password = ARGV
  abort 'usage: add LOGIN "FULL NAME" PASSWORD' if [login, name, password].any? { |x| x.to_s.empty? }

  if UsersService.find(login)
    abort "Пользователь '#{login}' уже существует. Используйте set-password для смены пароля."
  end
  UsersService.upsert(login: login, name: name, password: password)
  puts "Добавлен: #{login} (#{name})"

when 'set-password'
  login, password = ARGV
  abort 'usage: set-password LOGIN NEW_PASSWORD' if [login, password].any? { |x| x.to_s.empty? }

  user = UsersService.find(login)
  abort "Пользователь '#{login}' не найден." unless user
  UsersService.upsert(login: user[:login], name: user[:name], password: password)
  puts "Пароль обновлён: #{login}"

when 'delete'
  login = ARGV[0]
  abort 'usage: delete LOGIN' if login.to_s.empty?

  abort "Пользователь '#{login}' не найден." unless UsersService.find(login)
  UsersService.delete(login)
  puts "Удалён: #{login}"

else
  warn 'Использование:'
  warn '  ruby scripts/users_cli.rb list'
  warn '  ruby scripts/users_cli.rb add LOGIN "FULL NAME" PASSWORD'
  warn '  ruby scripts/users_cli.rb set-password LOGIN NEW_PASSWORD'
  warn '  ruby scripts/users_cli.rb delete LOGIN'
  exit 1
end
