# frozen_string_literal: true

module MultiBackgroundJob
  class UniqueJob
    VALID_OPTIONS = {
      across: %i[queue systemwide],
      timeout: 604800, # 1 week
      unlock_policy: %i[success start],
    }.freeze

    attr_reader :across, :timeout, :unlock_policy, :lock

    # @options [Hash] Unique definitions
    # @option [Symbol] :across Valid options are :queue and :systemwide. If jobs should not to be duplicated on
    #   current queue or the entire system
    # @option [Integer] :timeout Amount of times in seconds. Timeout decides how long to wait for acquiring the lock.
    #   A default timeout is defined to 1 week so unique locks won't last forever.
    # @option [Symbol] :unlock_policy Control when the unique lock is removed. The default value is `success`.
    #   The job will not unlock until it executes successfully, it will remain locked even if it raises an error and
    #   goes into the retry queue. The alternative value is `start` the job will unlock right before it starts executing
    def initialize(across: :queue, timeout: nil, unlock_policy: :success, lock: nil)
      unless VALID_OPTIONS[:across].include?(across.to_sym)
        raise Error, format('Invalid `across: %<given>p` option. Only %<expected>p are allowed.',
          given: across,
          expected: VALID_OPTIONS[:across])
      end
      unless VALID_OPTIONS[:unlock_policy].include?(unlock_policy.to_sym)
        raise Error, format('Invalid `unlock_policy: %<given>p` option. Only %<expected>p are allowed.',
          given: unlock_policy,
          expected: VALID_OPTIONS[:unlock_policy])
      end
      timeout = VALID_OPTIONS[:timeout] if timeout.to_i <= 0

      @across = across.to_sym
      @timeout = timeout.to_i
      @unlock_policy = unlock_policy.to_sym
      @lock = lock if lock.is_a?(MultiBackgroundJob::Lock)
    end

    def self.coerce(value)
      return unless value.is_a?(Hash)

      lock = MultiBackgroundJob::Lock.coerce(value['lock'] || value[:lock])
      new(
        across: (value['across'] || value[:across] || :queue).to_sym,
        timeout: (value['timeout'] || value[:timeout] || nil),
        unlock_policy: (value['unlock_policy'] || value[:unlock_policy] || :success).to_sym,
        lock: lock,
      )
    end

    def ttl
      Time.now.to_f + timeout
    end

    def to_hash
      {
        'across' => (across.to_s if across),
        'timeout' => timeout,
        'unlock_policy' => (unlock_policy.to_s if unlock_policy),
      }.tap do |hash|
        hash['lock'] = lock.to_hash if lock
      end
    end

    def eql?(other)
      return false unless other.is_a?(self.class)

      [across, timeout, unlock_policy] == [other.across, other.timeout, other.unlock_policy]
    end
    alias == eql?
  end
end
