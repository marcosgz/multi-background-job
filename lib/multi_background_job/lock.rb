# frozen_string_literal: true

module MultiBackgroundJob
  # Class Lock provides access to redis "sorted set" used to control unique jobs
  class Lock
    attr_reader :digest, :lock_id, :ttl

    # @param :digest [String] It's the uniq string used to group similar jobs
    # @param :lock_id [String] The uniq job id
    # @param :ttl [Float] The timestamp related lifietime of the lock before being discarded.
    def initialize(digest:, lock_id:, ttl:)
      @digest = digest
      @lock_id = lock_id
      @ttl = ttl
    end

    # Initialize a Lock object from hash
    #
    # @param value [Hash] Hash with lock properties
    # @return [MultiBackgroundJob::Lock, nil]
    def self.coerce(value)
      return unless value.is_a?(Hash)

      digest = value[:digest] || value['digest']
      lock_id = value[:lock_id] || value['lock_id']
      ttl = value[:ttl] || value['ttl']
      return if [digest, lock_id, ttl].any?(&:nil?)

      new(digest: digest, lock_id: lock_id, ttl: ttl)
    end

    # Remove expired locks from redis "sorted set"
    #
    # @param [String] digest It's the uniq string used to group similar jobs
    def self.flush_expired_members(digest, redis: nil)
      return unless digest

      caller = ->(redis) { redis.zremrangebyscore(digest, '-inf', "(#{now}") }

      if redis
        caller.(redis)
      else
        MultiBackgroundJob.redis_pool.with { |conn| caller.(conn) }
      end
    end

    # Remove all locks from redis "sorted set"
    #
    # @param [String] digest It's the uniq string used to group similar jobs
    def self.flush(digest, redis: nil)
      return unless digest

      caller = ->(conn) { conn.del(digest) }

      if redis
        caller.(redis)
      else
        MultiBackgroundJob.redis_pool.with { |conn| caller.(conn) }
      end
    end

    # Number of locks
    #
    # @param digest [String] It's the uniq string used to group similar jobs
    # @option [Number] from The begin of set. Default to 0
    # @option [Number] to The end of set. Default to the timestamp of 1 week from now
    # @return Number the amount of entries that within digest
    def self.count(digest, from: 0, to: nil, redis: nil)
      to ||= Time.now.to_f + MultiBackgroundJob::UniqueJob::VALID_OPTIONS[:timeout]
      caller = ->(conn) { conn.zcount(digest, from, to) }

      if redis
        caller.(redis)
      else
        MultiBackgroundJob.redis_pool.with { |conn| caller.(conn) }
      end
    end

    def to_hash
      {
        'ttl' => ttl,
        'digest' => (digest.to_s if digest),
        'lock_id' => (lock_id.to_s if lock_id),
      }
    end

    # @return [Float] A float timestamp of current time
    def self.now
      Time.now.to_f
    end

    # Remove lock_id lock from redis
    # @return [Boolean] Returns true when it's locked or false when there is no lock
    def unlock
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.zrem(digest, lock_id)
      end
    end

    # Adds lock_id lock to redis
    # @return [Boolean] Returns true when it's a fresh lock or false when lock already exists
    def lock
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.zadd(digest, ttl, lock_id)
      end
    end

    # Check if the lock_id lock exist
    # @return [Boolean] true or false when lock exist or not
    def locked?
      locked = false

      MultiBackgroundJob.redis_pool.with do |conn|
        timestamp = conn.zscore(digest, lock_id)
        return false unless timestamp

        locked = timestamp >= now
        self.class.flush_expired_members(digest, redis: conn)
      end

      locked
    end

    def eql?(other)
      return false unless other.is_a?(self.class)

      [digest, lock_id, ttl] == [other.digest, other.lock_id, other.ttl]
    end
    alias == eql?

    protected

    def now
      self.class.now
    end
  end
end
