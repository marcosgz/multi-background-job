# frozen_string_literal: true

require_relative './multi_background_job/version'
require_relative 'multi_background_job/errors'
require_relative 'multi_background_job/config'

module MultiBackgroundJob
  def self.config
    @config ||= Config.new
  end

  def self.configure(&block)
    return unless block_given?

    config.instance_eval(&block)
    @redis_pool = nil
    config
  end

  def self.redis_pool
    @redis_pool ||= ConnectionPool.new(config.redis_pool) do
      Redis.new(config.redis_config)
    end
  end
end
