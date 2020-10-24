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
        @payload['uniq'] = worker.job['uniq'] if worker.job['uniq']
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

        MultiBackgroundJob[payload['class'], **options].tap do |worker|
          worker.with_args(*Array(payload['args'])) if payload.key?('args')
          worker.with_job_jid(payload['jid']) if payload.key?('jid')
          worker.created_at(payload['created_at']) if payload.key?('created_at')
          worker.enqueued_at(payload['enqueued_at']) if payload.key?('enqueued_at')
          worker.at(payload['at']) if payload.key?('at')
          worker.unique(payload['uniq']) if payload.key?('uniq')
          if payload.key?('custom') && (custom_value = payload['custom']).is_a?(Hash)
            custom_value.each { |k, v| worker.with_custom(k, v) }
          end
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

      # Push sidekiq to the Sidekiq(Redis actually).
      #   * If job has the 'at' key. Then schedule it
      #   * Otherwise enqueue for immediate execution
      #
      # @return [Hash, NilClass] Payload that was sent to redis, or nil if job should be uniq and already exists
      def push
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

      protected

      def namespace
        MultiBackgroundJob.config.redis_namespace
      end

      def scheduled_queue_name
        "#{namespace}:schedule"
      end

      def immediate_queue_name
        "#{namespace}:queue:#{queue}"
      end

      def to_json(value)
        MultiJson.dump(value, mode: :compat)
      end
    end
  end
end
