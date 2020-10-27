# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MultiBackgroundJob errors' do

  describe 'MultiBackgroundJob::NotDefinedWorker' do
    specify do
      msg = <<~MSG.chomp
      The "MissingWorker" is not defined and the MultiBackgroundJob is configured to work on strict mode.
      it's highly recommended to include this worker class to the list of known workers.
      Example: `MultiBackgroundJob.configure { |config| config.workers = { "MissingWorker" => {} } }`
      Another option is to set config.strict = false
      MSG

      error = MultiBackgroundJob::NotDefinedWorker.new('MissingWorker')
      expect(error.message).to eq(msg)
    end
  end
end
