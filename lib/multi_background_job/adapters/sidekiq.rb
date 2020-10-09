# frozen_string_literal: true

require_relative '../lock'

module MultiBackgroundJob
  module Adapters
    # This is a Sidekiq adapter that converts MultiBackgroundJob::Worker object into a sidekiq readable format
    # and then push the jobs into the service.
    class Sidekiq < Adapter
      attr_reader :worker, :queue

      def initialize(worker)
        @worker = worker
        @queue = worker.options.fetch(:queue, 'default')

        @payload = {
          'class' => worker.worker_class,
          'args'  => worker.job.fetch('args', []),
          'jid'   => worker.job.fetch('jid'),
          'retry' => worker.options.fetch(:retry, true),
          'queue' => @queue,
          'created_at' => worker.job.fetch('created_at', Time.now.to_f),
        }
      end

      # Coerces the raw payload into an instance of Worker
      # @param payload [Hash] The job as json from redis
      # @options options [Hash] list of options that will be passed along to the Worker instance
      # @return [MultiBackgroundJob::Worker] and instance of MultiBackgroundJob::Worker
      def self.coerce_to_worker(payload, **options)
        raise(Error, 'invalid payload') unless payload.is_a?(Hash)
        raise(Error, 'invalid payload') unless payload['class'].is_a?(String)

        options[:retry] ||= payload['retry'] if payload.key?('retry')
        options[:queue] ||= payload['queue'] if payload.key?('queue')
        if (uniq_val = payload['uniq']).is_a?(Hash)
          options[:uniq] ||= {}
          options[:uniq][:across] ||= uniq_val['across']&.to_sym
          options[:uniq][:timeout] ||= uniq_val['timeout']
          options[:uniq][:unlock_policy] ||= uniq_val['unlock_policy']&.to_sym
        end

        MultiBackgroundJob[payload['class'], **options].tap do |worker|
          worker.with_args(*Array(payload['args'])) if payload.key?('args')
          worker.with_job_jid(payload['jid']) if payload.key?('jid')
          worker.created_at(payload['created_at']) if payload.key?('created_at')
          worker.enqueued_at(payload['enqueued_at']) if payload.key?('enqueued_at')
          worker.at(payload['at']) if payload.key?('at')
        end
      end

      # Initializes adapter and push job into the sidekiq service
      #
      # @param worker [MultiBackgroundJob::Worker] An instance of MultiBackgroundJob::Worker
      # @return [Hash] Job payload
      # @see push method for more details
      def self.push(worker)
        new(worker).push
      end

      # Initializes adapter and removes the uniq locking from redis
      #
      # @param worker [MultiBackgroundJob::Worker] An instance of MultiBackgroundJob::Worker
      # @return [Boolean] True or
      # @see push method for more details
      def self.acknowledge(worker)
        new(worker).acknowledge
      end

      # Push sidekiq to the Sidekiq(Redis actually).
      #   * if job has the 'uniq' key. Then check if already exist
      #   * If job has the 'at' key. Then schedule it
      #   * Otherwise enqueue for immediate execution
      #
      # @return [Hash, NilClass] Payload that was sent to redis, or nil if job should be uniq and already exists
      def push
        return if duplicate?

        @payload['enqueued_at'] = Time.now.to_f
        if (timestamp = worker.job['at'])
          MultiBackgroundJob.redis_pool.with do |redis|
            redis.zadd(scheduled_queue_name, timestamp.to_f.to_s, to_json(@payload))
          end
        else
          MultiBackgroundJob.redis_pool.with do |redis|
            redis.lpush(immediate_queue_name, to_json(@payload))
          end
        end
        @payload
      end

      # Removes the uniqueness locking from redis
      #
      # @return [Boolean, NilClass] Returns the redis response for the ZREM comand, or nil when
      #   worker does not implement the uniqueness rule
      def acknowledge
        return unless uniqueness?

        uniqueness_lock&.unlock
      end

      protected

      def uniqueness_lock
        return unless uniqueness?

        Lock.new(
          digest: LockDigest.new('sidekiq', queue, across: worker.options.dig(:uniq, :across)).to_s,
          job_id: job_lock_id,
          ttl: now + worker.options.dig(:uniq, :timeout),
        )
      end

      def namespace
        MultiBackgroundJob.config.redis_namespace
      end

      def uniqueness?
        !!worker.options[:uniq]
      end

      def scheduled_queue_name
        "#{namespace}:schedule"
      end

      def immediate_queue_name
        "#{namespace}:queue:#{queue}"
      end

      # This method uses an external queue to control duplications. It has no sidekiq connection.
      # We are using Worker Class and its Arguments to generate a hexdigest as a locking key. And
      # before enqueue new jobs we check if we have a "lock" active. The TTL of a lock is 1 week. Just
      # to ensure locks won't last forever. When the job is executed this lock is removed allowing for an
      # equal job to be queued again.
      # @return [Boolean] True or False if already exist a lock for this job.
      def duplicate?
        return false unless uniqueness?
        return true if uniqueness_lock.locked?

        @payload['uniq'] = worker.options.fetch(:uniq).each_with_object({}) do |(key, val), memo|
          memo[key.to_s] = val.is_a?(Symbol) ? val.to_s : val
        end
        @payload['uniq']['ttl'] = uniqueness_lock.ttl
        uniqueness_lock.lock

        false
      end

      # Generage a uniq hexdigest using job class name and args
      def job_lock_id
        @job_lock_id ||= Digest::SHA256.hexdigest to_json(@payload.values_at('class', 'args'))
      end

      def now
        Time.now.to_f
      end

      def to_json(value)
        MultiJson.dump(value, mode: :compat)
      end
    end
  end
end
