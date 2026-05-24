# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    add_group 'Services', 'services'
    add_group 'Storage', 'storage'
    add_group 'Web', 'web'
  end
end

require_relative 'support/database'

SpecDatabase.setup_env!

require 'rspec'
require 'rack/test'

%w[database factories api_helpers].each do |name|
  require_relative "support/#{name}"
end
require_relative 'support/app'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'tmp/rspec_examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.before(:suite) do
    SpecDatabase.prepare_suite!
  end

  config.before(:each) do
    SpecDatabase.reset!
  end

  config.include Rack::Test::Methods, type: :request
  config.include ApiHelpers, type: :request
end
