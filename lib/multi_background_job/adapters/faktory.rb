# frozen_string_literal: true

module MultiBackgroundJob
  module Adapters
    # This is a Faktory adapter that converts MultiBackgroundJob::Worker object into a faktory readable format
    # and then push the jobs into the service.
    class Faktory < Adapter
      attr_reader :worker, :queue

      def initialize(worker)
        @worker = worker
        @queue = worker.options.fetch(:queue, 'default')

        @payload = worker.payload.merge(
          'jobtype' => worker.worker_class,
          'queue'   => @queue,
          'retry'   => parse_retry(worker.options[:retry]),
        )
        @payload['created_at'] ||= Time.now.to_f
      end

      # Coerces the raw payload into an instance of Worker
      # @param payload [Hash] The job as json from redis
      # @options options [Hash] list of options that will be passed along to the Worker instance
      # @return [MultiBackgroundJob::Worker] and instance of MultiBackgroundJob::Worker
      def self.coerce_to_worker(payload, **options)
        raise(Error, 'invalid payload') unless payload.is_a?(Hash)
        raise(Error, 'invalid payload') unless payload['jobtype'].is_a?(String)

        options[:retry] ||= payload['retry'] if payload.key?('retry')
        options[:queue] ||= payload['queue'] if payload.key?('queue')

        MultiBackgroundJob[payload['jobtype'], **options].tap do |worker|
          worker.with_args(*Array(payload['args'])) if payload.key?('args')
          worker.with_job_jid(payload['jid']) if payload.key?('jid')
          worker.created_at(payload['created_at']) if payload.key?('created_at')
          worker.enqueued_at(payload['enqueued_at']) if payload.key?('enqueued_at')
          worker.at(payload['at']) if payload.key?('at')
          worker.unique(payload['uniq']) if payload.key?('uniq')
        end
      end

      # Initializes adapter and push job into the faktory service
      #
      # @param worker [MultiBackgroundJob::Worker] An instance of MultiBackgroundJob::Worker
      # @return [Hash] Job payload
      # @see push method for more details
      def self.push(worker)
        new(worker).push
      end

      # Push job to Faktory
      #   * If job has the 'at' key. Then schedule it
      #   * Otherwise enqueue for immediate execution
      #
      # @raise [MultiBackgroundJob::Error] raise and error when faktory dependency is not loaded
      # @return [Hash] Payload that was sent to server
      def push
        unless Object.const_defined?(:Faktory)
          raise MultiBackgroundJob::Error, <<~ERR
          Faktory client for ruby is not loaded. You must install and require https://github.com/contribsys/faktory_worker_ruby.
          ERR
        end
        @payload['enqueued_at'] ||= Time.now.to_f
        {'created_at' => false, 'enqueued_at' => false, 'at' => true}.each do |field, past_remove|
          # Optimization to enqueue something now that is scheduled to go out now or in the past
          if (time = @payload.delete(field)) &&
              (!past_remove || (past_remove && time > Time.now.to_f))
            @payload[field] = parse_time(time)
          end
        end

        pool = Thread.current[:faktory_via_pool] || ::Faktory.server_pool
        ::Faktory.client_middleware.invoke(@payload, pool) do
          pool.with do |c|
            c.push(@payload)
          end
        end
        @payload
      end

      protected

      # Convert worker retry value acording to the Go struct datatype.
      #
      # * 25 is the default.
      # * 0 means the job is completely ephemeral. No matter if it fails or succeeds, it will be discarded.
      # * -1 means the job will go straight to the Dead set if it fails, no retries.
      def parse_retry(value)
        case value
        when Numeric then value.to_i
        when false then -1
        else
          25
        end
      end

      def parse_time(value)
        case value
        when Numeric then Time.at(value).to_datetime.rfc3339(9)
        when Time then value.to_datetime.rfc3339(9)
        when DateTime then value.rfc3339(9)
        end
      end

      def to_json(value)
        MultiJson.dump(value, mode: :compat)
      end
    end
  end
end
