# frozen_string_literal: true

require_relative './unique_job'

module MultiBackgroundJob
  class Worker
    attr_reader :options, :payload, :worker_class, :unique_job

    attr_reader :arguments

    def initialize(worker_class, **options)
      @worker_class = worker_class
      @options = options
      @payload = {}
      unique(@options.delete(:uniq)) if @options.key?(:uniq)
    end

    def self.coerce(service:, payload:, **opts)
      SERVICES.fetch(service).coerce_to_worker(payload, **opts)
    end

    %i[created_at enqueued_at].each do |method_name|
      define_method method_name do |value|
        @payload[method_name.to_s] = \
          case value
          when Numeric then value.to_f
          when String then Time.parse(value).to_f
          when Time, DateTime then value.to_f
          else
            raise ArgumentError, format('The %<v>p is not a valid value for %<m>s.', v: value, m: method_name)
          end

        self
      end
    end

    # Adds arguments to the job
    # @return self
    def with_args(*args)
      @payload['args'] = args

      self
    end

    # Schedule the time when a job will be executed. Jobs which are scheduled in the past are enqueued for immediate execution.
    # @param timestamp [Numeric] timestamp, numeric or something that acts numeric.
    # @return self
    def in(timestamp)
      now = Time.now.to_f
      timestamp = Time.parse(timestamp) if timestamp.is_a?(String)
      int = timestamp.respond_to?(:strftime) ? timestamp.to_f : now + timestamp.to_f
      return self if int <= now

      @payload['at'] = int
      @payload['created_at'] = now

      self
    end
    alias_method :at, :in

    # Wrap uniq options
    #
    # @param value [Hash] Unique configurations with `across`, `timeout` and `unlock_policy`
    # @return self
    def unique(value)
      value = {} if value == true
      @unique_job = \
        case value
        when Hash then UniqueJob.coerce(value)
        when UniqueJob then value
        else
          nil
        end

      self
    end

    def with_job_jid(jid = nil)
      @payload['jid'] ||= jid || MultiBackgroundJob.jid

      self
    end

    # @param :to [Symbol] Adapter key
    # @return Response of service
    # @see MultiBackgroundJob::Adapters::** for more details
    def push(to: nil)
      to ||= options[:service]
      unless SERVICES.include?(to)
        raise Error, format('Service %<to>p is not implemented. Please use one of %<list>p', to: to, list: SERVICES.keys)
      end

      @payload['created_at'] ||= Time.now.to_f
      worker_to_push = with_job_jid
      MultiBackgroundJob.config.middleware.invoke(worker_to_push, to) do
        SERVICES[to].push(worker_to_push)
      end
    end

    def eql?(other)
      return false unless other.is_a?(self.class)

      worker_class == other.worker_class && \
        payload == other.payload &&
        options == other.options &&
        unique_job == other.unique_job
    end
    alias == eql?

    def unique_job?
      unique_job.is_a?(UniqueJob)
    end
  end
end
