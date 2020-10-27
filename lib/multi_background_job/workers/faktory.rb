# frizen_string_literal: true

require_relative './shared_class_methods'

module MultiBackgroundJob
  module Workers
    module Faktory
      def self.extended(base)
        base.include(::Faktory::Job) if defined?(::Faktory)
        base.extend SharedClassMethods
        base.extend ClassMethods
      end

      module ClassMethods
        def service_worker_options
          default_queue = MultiBackgroundJob.config.workers.dig(self.name, :queue)
          default_retry = MultiBackgroundJob.config.workers.dig(self.name, :retry)
          default_queue ||= ::Faktory.default_job_options['queue'] if defined?(::Faktory)
          default_retry ||= ::Faktory.default_job_options['retry'] if defined?(::Faktory)
          {
            queue: (default_queue || 'default'),
            retry: (default_retry || 25),
          }
        end
      end
    end
  end
end
