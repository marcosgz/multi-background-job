# frizen_string_literal: true

require_relative './shared_class_methods'

module MultiBackgroundJob
  module Workers
    module Faktory
      def self.included(base)
        # @TODO Add faktory here
        base.extend SharedClassMethods
      end
    end
  end
end
