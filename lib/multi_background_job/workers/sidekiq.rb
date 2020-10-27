# frizen_string_literal: true

require_relative './shared_class_methods'

module MultiBackgroundJob
  module Workers
    module Sidekiq
      def self.extended(base)
        base.include(::Sidekiq::Worker) if defined?(::Sidekiq)
        base.extend SharedClassMethods
        base.extend ClassMethods
      end

      module ClassMethods
        def service_worker_options
          default_queue = MultiBackgroundJob.config.workers.dig(self.name, :queue)
          default_retry = MultiBackgroundJob.config.workers.dig(self.name, :retry)
          default_queue ||= ::Sidekiq.default_worker_options['queue'] if defined?(::Sidekiq)
          default_retry ||= ::Sidekiq.default_worker_options['retry'] if defined?(::Sidekiq)
          {
            queue: (default_queue || 'default'),
            retry: (default_retry || 15),
          }
        end
      end
    end
  end
end
