# frozen_string_literal: true

module MultiBackgroundJob
  class Worker
    attr_reader :options, :job, :worker_class

    UNIQ_ARGS = {
      across: %i[queue systemwide],
      timeout: 604800, # 1 week
      unlock_policy: %i[success start],
    }.freeze

    def initialize(worker_class, **options)
      @worker_class = worker_class
      @options = options
      @job = {}
      if @options.key?(:uniq)
        value = @options.delete(:uniq)
        value = {} if value == true
        setup_uniq_option(**value) if value.is_a?(Hash)
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
      worker_class == other.worker_class && job == other.job && options == other.options
    end
    alias == eql?

    protected

    # @options [Hash] Uniq definitions
    # @option [Symbol] :across Valid options are :queue and :systemwide. If jobs should not to be duplicated on
    #   current queue or the entire system
    # @option [Integer] :timeout Amount of times in seconds. Timeout decides how long to wait for acquiring the lock.
    #   A default timeout is defined to 1 week so unique locks won't last forever.
    # @option [Symbol] :unlock_policy Control when the unique lock is removed. The default value is `success`.
    #   The job will not unlock until it executes successfully, it will remain locked even if it raises an error and
    #   goes into the retry queue. The alternative value is `start` the job will unlock right before it starts executing
    # @return self
    def setup_uniq_option(across: :queue, timeout: nil, unlock_policy: :success)
      unless UNIQ_ARGS[:across].include?(across.to_sym)
        raise Error, format('Invalid `across: %<given>p` option. Only %<expected>p are allowed.', given: across, expected: UNIQ_ARGS[:across])
      end
      unless UNIQ_ARGS[:unlock_policy].include?(unlock_policy.to_sym)
        raise Error, format('Invalid `unlock_policy: %<given>p` option. Only %<expected>p are allowed.', given: unlock_policy, expected: UNIQ_ARGS[:unlock_policy])
      end
      timeout = UNIQ_ARGS[:timeout] if timeout.to_i <= 0

      @options[:uniq] = {
        across: across.to_sym,
        timeout: timeout.to_i,
        unlock_policy: unlock_policy.to_sym,
      }
    end
  end
end
