# frozen_string_literal: true
# Прогон цепочки login/me/logout по живому HTTP, чтобы не упираться в
# проблемы кодировки windows-bash + curl.

require 'net/http'
require 'uri'
require 'json'

BASE = 'http://127.0.0.1:4567'

def show(label, code, body, cookies)
  puts "[#{label}] HTTP #{code}#{cookies ? "  cookies=#{cookies.size}" : ''}"
  puts "  body: #{body[0, 200]}"
end

# 1. me — без сессии должен дать 401
http = Net::HTTP.new('127.0.0.1', 4567)
res = http.get('/api/auth/me')
show('me (anon)', res.code, res.body, nil)

# 2. login Балашов / 12345678
req = Net::HTTP::Post.new('/api/auth/login', 'Content-Type' => 'application/json; charset=utf-8')
req.body = JSON.generate(login: 'Балашов', password: '12345678')
res = http.request(req)
cookie = res['set-cookie']
show('login', res.code, res.body, [cookie].compact)

# 3. me с cookie — должен вернуть пользователя
session_cookie = cookie&.split(';')&.first
req = Net::HTTP::Get.new('/api/auth/me')
req['Cookie'] = session_cookie if session_cookie
res = http.request(req)
show('me (logged in)', res.code, res.body, nil)

# 4. журнал с cookie — должен пройти
req = Net::HTTP::Get.new('/api/journal/weeks')
req['Cookie'] = session_cookie if session_cookie
res = http.request(req)
show('journal/weeks (auth)', res.code, res.body[0, 100], nil)

# 5. журнал БЕЗ cookie — должен 401
res = http.get('/api/journal/weeks')
show('journal/weeks (anon)', res.code, res.body, nil)

# 6. login с неверным паролем
req = Net::HTTP::Post.new('/api/auth/login', 'Content-Type' => 'application/json; charset=utf-8')
req.body = JSON.generate(login: 'Балашов', password: 'wrong')
res = http.request(req)
show('bad login', res.code, res.body, nil)

# 7. logout
req = Net::HTTP::Post.new('/api/auth/logout', 'Content-Type' => 'application/json; charset=utf-8')
req['Cookie'] = session_cookie if session_cookie
req.body = '{}'
res = http.request(req)
show('logout', res.code, res.body, nil)
