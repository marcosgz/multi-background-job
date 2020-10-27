# frozen_string_literal: true

# Server midleware for Faktory
#
# @see https://github.com/contribsys/faktory_worker_ruby/wiki/Middleware
module MultiBackgroundJob
  module Middleware
    class UniqueJob
      module Faktory
        def self.bootstrap
          if defined?(::Faktory)
            ::Faktory.configure_worker do |config|
              config.worker_middleware do |chain|
                chain.add Worker
              end
            end
          end
        end

        # Worker middleware runs around the execution of a job
        class Worker
          def call(_jobinst, payload)
            if payload.is_a?(Hash) && (unique_lock = unique_job_lock(payload))
              unique_lock.unlock
            end
            yield
          end

          protected

          def unique_job_lock(payload)
            return unless payload['uniq'].is_a?(Hash)

            unique_job = ::MultiBackgroundJob::UniqueJob.coerce(payload['uniq'])
            unique_job&.lock
          end
        end
      end
    end
  end
end
