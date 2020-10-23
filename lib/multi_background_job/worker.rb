# frozen_string_literal: true

require_relative './unique_job'

module MultiBackgroundJob
  class Worker
    attr_reader :options, :job, :worker_class, :unique_job

    def initialize(worker_class, **options)
      @worker_class = worker_class
      @options = options
      @job = {}
      if @options.key?(:uniq)
        value = @options.delete(:uniq)
        value = {} if value == true
        @unique_job = UniqueJob.new(value) if value.is_a?(Hash)
      end
    end

    def self.coerce(service:, payload:, **opts)
      SERVICES.fetch(service).coerce_to_worker(payload, **opts)
    end

    %i[created_at enqueued_at].each do |method_name|
      define_method method_name do |value|
        @job[method_name.to_s] = value

        self
      end
    end

    # Adds arguments to the job
    # @return self
    def with_args(*args)
      @job['args'] = args

      self
    end

    # Schedule the time when a job will be executed. Jobs which are scheduled in the past are enqueued for immediate execution.
    # @param timestamp [Number] timestamp, numeric or something that acts numeric.
    # @return self
    def in(timestamp)
      now = Time.now.to_f
      int = timestamp.respond_to?(:strftime) ? timestamp.to_f : now + timestamp.to_f
      return self if int <= now

      @job['at'] = int
      @job['created_at'] = now

      self
    end
    alias_method :at, :in

    def with_job_jid(jid = nil)
      @job['jid'] ||= jid || MultiBackgroundJob.jid

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

      @job['created_at'] ||= Time.now.to_f
      SERVICES[to].push(with_job_jid)
    end

    # @param :to [Symbol] Adapter key
    # @return Response of service
    # @see MultiBackgroundJob::Adapters::** for more details
    def acknowledge(to: nil)
      to ||= options[:service]
      unless SERVICES.include?(to)
        raise Error, format('Service %<to>p is not implemented. Please use one of %<list>p', to: to, list: SERVICES.keys)
      end

      SERVICES[to].acknowledge(self)
    end

    def eql?(other)
      worker_class == other.worker_class && \
        job == other.job &&
        options == other.options &&
        unique_job == other.unique_job
    end
    alias == eql?
  end
end
