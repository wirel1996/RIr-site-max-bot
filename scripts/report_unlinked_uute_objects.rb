#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative '../storage/uute_db'

rows = UuteDB.with_db do |db|
  db.execute(
    "SELECT id, identifier, name, address, source_key FROM uute_objects WHERE category='gspo' AND (object_id IS NULL OR object_id <= 0) ORDER BY id"
  )
end

puts JSON.pretty_generate(
  total: rows.size,
  rows: rows.map do |r|
    {
      id: r['id'].to_i,
      identifier: r['identifier'].to_s.strip,
      name: r['name'].to_s.strip,
      address: r['address'].to_s.strip,
      source_key: r['source_key'].to_s
    }
  end
)
