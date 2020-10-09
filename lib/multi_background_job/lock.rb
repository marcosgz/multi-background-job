# frozen_string_literal: true

module MultiBackgroundJob
  # Class Lock provides access to redis "sorted set" used to control unique jobs
  class Lock
    attr_reader :digest, :job_id, :ttl

    # @param :digest [String] It's the uniq string used to group similar jobs
    # @param :job_id [String] The uniq job id
    # @param :ttl [Float] The timestamp related lifietime of the lock before being discarded.
    def initialize(digest:, job_id:, ttl:)
      @digest = digest
      @job_id = job_id
      @ttl = ttl
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

    # @return [Float] A float timestamp of current time
    def self.now
      Time.now.to_f
    end

    # Remove job_id lock from redis
    # @return [Boolean] Returns true when it's locked or false when there is no lock
    def unlock
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.zrem(digest, job_id)
      end
    end

    # Adds job_id lock to redis
    # @return [Boolean] Returns true when it's a fresh lock or false when lock already exists
    def lock
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.zadd(digest, ttl, job_id)
      end
    end

    # Check if the job_id lock exist
    # @return [Boolean] true or false when lock exist or not
    def locked?
      locked = false

      MultiBackgroundJob.redis_pool.with do |conn|
        timestamp = conn.zscore(digest, job_id)
        return false unless timestamp

        locked = timestamp >= now
        self.class.flush_expired_members(digest, redis: conn)
      end

      locked
    end

    protected

    def now
      self.class.now
    end
  end
end