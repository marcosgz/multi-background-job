# frozen_string_literal: true

require 'multi_background_job/lock'
require 'multi_background_job/lock_digest'

module MultiBackgroundJob
  module Middleware
    # This middleware uses an external redis queue to control duplications. The locking key
    # is composed of worker class and its arguments. Before enqueue new jobs it will check if have a "lock" active.
    # The TTL of lock is 1 week as default. TTL is important to ensure locks won't last forever.
    class UniqueJob
      def self.bootstrap(service:)
        services = Dir[File.expand_path('../unique_job/*.rb', __FILE__)].map { |f| File.basename(f, '.rb').to_sym }
        unless services.include?(service)
          msg = "UniqueJob is not supported for the `%<service>p' service. Supported options are: %<services>s."
          raise MultiBackgroundJob::Error, format(msg, service: service.to_sym, services: services.map { |s| "`:#{s}'" }.join(', '))
        end
        if (require("multi_background_job/middleware/unique_job/#{service}"))
          class_name = service.to_s.split('_').collect!{ |w| w.capitalize }.join
          MultiBackgroundJob::Middleware::UniqueJob.const_get(class_name).bootstrap
        end

        MultiBackgroundJob.configure do |config|
          config.unique_job_active = true
          config.middleware.add(UniqueJob)
        end
      end

      def call(worker, service)
        if MultiBackgroundJob.config.unique_job_active? &&
            (uniq_lock = unique_job_lock(worker: worker, service: service))
          return false if uniq_lock.locked? # Don't push job to server

          # Add unique job information to the job payload
          worker.unique_job.lock = uniq_lock
          worker.payload['uniq'] = worker.unique_job.to_hash

          uniq_lock.lock
        end

        yield
      end

      protected

      def unique_job_lock(worker:, service:)
        return unless worker.unique_job?

        digest = LockDigest.new(
          *[service || worker.options[:service], worker.options[:queue]].compact,
          across: worker.unique_job.across,
        )

        Lock.new(
          digest: digest.to_s,
          lock_id: unique_job_lock_id(worker),
          ttl: worker.unique_job.ttl,
        )
      end

      def unique_job_lock_id(worker)
        identifier_data = [worker.worker_class, worker.payload.fetch('args'.freeze, [])]
        Digest::SHA256.hexdigest(
          MultiJson.dump(identifier_data, mode: :compat),
        )
      end
    end
  end
end
