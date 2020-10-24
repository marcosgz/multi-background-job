# frozen_string_literal: true

require 'multi_background_job/lock'
require 'multi_background_job/lock_digest'

module MultiBackgroundJob
  module Middleware
    # This middleware uses an external redis queue to control duplications. The locking key
    # is composed of worker class and its arguments. Before enqueue new jobs it will check if have a "lock" active.
    # The TTL of lock is 1 week as default. TTL is important to ensure locks won't last forever.
    class UniqueJobMiddleware
      def self.bootstrap
        MultiBackgroundJob.configure do |config|
          config.middleware.add(UniqueJobMiddleware)
        end
      end

      def call(worker, service)
        if (uniq_lock = unique_job_lock(worker: worker, service: service))
          return false if uniq_lock.locked? # Don't push job to server

          # Add unique job information to the job payload
          worker.job['uniq'] = worker.unique_job.as_json.merge(
            'ttl' => uniq_lock.ttl,
          )
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
          job_id: unique_job_lock_id(worker),
          ttl: worker.unique_job.ttl,
        )
      end

      def unique_job_lock_id(worker)
        identifier_data = [worker.worker_class, worker.job.fetch('args'.freeze, [])]
        Digest::SHA256.hexdigest(
          MultiJson.dump(identifier_data, mode: :compat),
        )
      end
    end
  end
end
