# frozen_string_literal: true

module MultiBackgroundJob
  # Class Lock generates the uniq digest acording to the uniq config
  class LockDigest
    BASE = 'uniqueness'.freeze
    SEPARATOR = ':'.freeze

    def initialize(*keys, across:)
      @keys = keys.map { |k| k.to_s.strip.downcase }
      @across = across.to_sym
    end

    def to_s
      case @across
      when :systemwide
        build_name(*@keys.slice(0..-2))
      when :queue
        build_name(*@keys)
      else
        raise Error, format(
          'Could not resolve the lock digest using across %<across>p. ' +
          'Valid options are :systemwide and :queue',
          across: @across,
        )
      end
    end

    private

    def build_name(*segments)
      [namespace, BASE, *segments].compact.join(SEPARATOR)
    end

    def namespace
      MultiBackgroundJob.config.redis_namespace
    end
  end
end
