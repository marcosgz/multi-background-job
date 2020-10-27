# frizen_string_literal: true

require 'redis'
require 'connection_pool'

require_relative './middleware_chain'

module MultiBackgroundJob
  class Config
    class << self
      private

      def attribute_accessor(field, validator: nil, normalizer: nil, default: nil)
        normalizer ||= :"normalize_#{field}"
        validator ||= :"validate_#{field}"

        define_method(field) do
          unless instance_variable_defined?(:"@#{field}")
            fallback = config_from_yaml[field.to_s] || default
            return unless fallback

            send(:"#{field}=", fallback.respond_to?(:call) ? fallback.call : fallback)
          end
          instance_variable_get(:"@#{field}")
        end

        define_method(:"#{field}=") do |value|
          value = send(normalizer, field, value) if respond_to?(normalizer, true)
          send(validator, field, value) if respond_to?(validator, true)

          instance_variable_set(:"@#{field}", value)
        end
      end
    end

    # Path to the YAML file with configs
    attr_accessor :config_path

    # ConnectionPool options for redis
    attribute_accessor :redis_pool_size, default: 5, normalizer: :normalize_to_int, validator: :validate_greater_than_zero
    attribute_accessor :redis_pool_timeout, default: 5, normalizer: :normalize_to_int, validator: :validate_greater_than_zero

    # Namespace used to manage internal data like unique job verification data.
    attribute_accessor :redis_namespace, default: 'multi-bg'

    # List of configurations to be passed along to the Redis.new
    attribute_accessor :redis_config, default: {}

    # A Hash with all workers definitions. The worker class name must be the main hash key
    # Example:
    #   "Accounts::ConfirmationEmailWorker":
    #     retry: false
    #     queue: "mailer"
    #   "Elastic::BatchIndex":
    #     retry: 5
    #     queue: "elasticsearch"
    #     adapter: "faktory"
    attribute_accessor :workers, default: {}

    # Does not validate if it's  when set to false
    attribute_accessor :strict, default: true
    alias strict? strict

    def worker_options(class_name)
      class_name = class_name.to_s
      if strict? && !workers.key?(class_name)
        raise NotDefinedWorker.new(class_name)
      end

      workers.fetch(class_name, {})
    end

    def redis_pool
      {
        size: redis_pool_size,
        timeout: redis_pool_timeout,
      }
    end

    def middleware
      @middleware ||= MiddlewareChain.new
      yield @middleware if block_given?
      @middleware
    end

    def config_path=(value)
      @config_from_yaml = nil
      @config_path = value
    end

    private

    def normalize_to_int(_attribute, value)
      value.to_i
    end

    def validate_greater_than_zero(attribute, value)
      return if value > 0

      raise InvalidConfig, format(
        'The %<value>p for %<attr>s is not valid. It must be greater than zero',
        value: value,
        attr: attribute,
      )
    end

    def normalize_redis_config(_attribute, value)
      case value
      when String
        { url: value }
      when Hash
        value.each_with_object({}) { |(k, v), r| r[k.to_sym] = v }
      else
        value
      end
    end

    def validate_redis_config(attribute, value)
      return if value.is_a?(Hash)

      raise InvalidConfig, format(
        'The %<value>p for %<attr>i is not valid. It must be a Hash with the redis initialization options. ' +
        'See https://github.com/redis/redis-rb for all available options',
        value: value,
        attr: attribute,
      )
    end

    def normalize_workers(_, value)
      return unless value.is_a?(Hash)

      hash = {}
      value.each do |class_name, opts|
        hash[class_name.to_s] = opts.each_with_object({}) { |(k,v), r| r[k.to_sym] = v }
      end
      hash
    end

    def config_from_yaml
      return {} unless config_path

      @config_from_yaml ||= begin
        YAML.load_file(config_path)
      rescue Errno::ENOENT, Errno::ESRCH
        {}
      end
    end
  end
end

