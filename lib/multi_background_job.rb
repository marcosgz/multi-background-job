# frozen_string_literal: true

require 'yaml'
require 'securerandom'
require 'multi_json'

require_relative './multi_background_job/version'
require_relative 'multi_background_job/errors'
require_relative 'multi_background_job/config'
require_relative 'multi_background_job/worker'
require_relative 'multi_background_job/adapters/adapter'
require_relative 'multi_background_job/adapters/sidekiq'
require_relative 'multi_background_job/adapters/faktory'

# This is a central point of our background job queue system.
# We have more external services like API and Lme that queue jobs for pipeline processing.
# So that way all services can share the same codebase and avoid incompatibility issues
#
# Example:
#
# Standard job.
#   MultiBackgroundJob['UserWorker', queue: 'default']
#     .with_args(1)
#     .push(to: :sidekiq)
#
# Schedule the time when a job will be executed.
#   MultiBackgroundJob['UserWorker']
#     .with_args(1)
#     .at(timestamp)
#     .push(to: :sidekiq)
#   MultiBackgroundJob['UserWorker']
#     .with_args(1)
#     .in(10.minutes)
#     .push(to: :sidekiq)
#
# Unique jobs.
#   MultiBackgroundJob['UserWorker', uniq: { across: :queue, timeout: 1.minute, unlock_policy: :start }]
#     .with_args(1)
#     .push(to: :sidekiq)
module MultiBackgroundJob
  SERVICES = {
    sidekiq: Adapters::Sidekiq,
    faktory: Adapters::Faktory,
  }

  # @param worker_class [String] The worker class name
  # @param options [Hash] Options that will be passed along to the worker instance
  # @return [MultiBackgroundJob::Worker] An instance of worker
  def self.[](worker_class, **options)
    Worker.new(worker_class, **config.worker_options(worker_class).merge(options))
  end

  def self.jid
    SecureRandom.hex(12)
  end

  def self.for(service, **options)
    require_relative "multi_background_job/workers/#{service}"
    service = service.to_sym
    worker_options = options.merge(service: service)
    module_name = service.to_s.split(/_/i).collect!{ |w| w.capitalize }.join
    mod = Workers.const_get(module_name)
    mod.module_eval do
      define_method(:bg_worker_options) do
        worker_options
      end
    end
    mod
  end

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
