# frozen_string_literal: true

require 'timecop'

module Hooks
  module Timecop
    def self.included(base)
      base.before(:each) do |example|
        if example.metadata[:freeze_at]
          ::Timecop.freeze(*example.metadata[:freeze_at])
        end
      end

      base.after(:each) do |example|
        ::Timecop.return if example.metadata[:freeze_at]
      end
    end
  end
end
