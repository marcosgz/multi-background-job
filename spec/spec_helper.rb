# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'pry'
require 'support/hooks/timecop'
require 'multi_background_job'

MINUTE_IN_SECONDS = 60
HOUR_IN_SECONDS = MINUTE_IN_SECONDS * 60
DAY_IN_SECONDS = HOUR_IN_SECONDS * 24
WEEK_IN_SECONDS = DAY_IN_SECONDS * 7

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.include Hooks::Timecop
end
