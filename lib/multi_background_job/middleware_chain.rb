# frozen_string_literal: true

module MultiBackgroundJob
  # Middleware is code configured to run before/after push a new job.
  # It is patterned after Rack middleware for some modification before push the job to the server
  #
  # To add a middleware:
  #
  # MultiBackgroundJob.configure do |config|
  #   config.middleware do |chain|
  #     chain.add MyMiddleware
  #   end
  # end
  #
  # This is an example of a minimal middleware, note the method must return the result
  # or the job will not push the server.
  #
  # class MyMiddleware
  #   def call(job, conn_pool)
  #     puts "Before push"
  #     result = yield
  #     puts "After push"
  #     result
  #   end
  # end
  #
  class MiddlewareChain
    include Enumerable
    attr_reader :entries

    def initialize_copy(copy)
      copy.instance_variable_set(:@entries, entries.dup)
    end

    def each(&block)
      entries.each(&block)
    end

    def initialize
      @entries = []
      yield self if block_given?
    end

    def remove(klass)
      entries.delete_if { |entry| entry.klass == klass }
    end

    def add(klass, *args)
      remove(klass) if exists?(klass)
      entries << Entry.new(klass, *args)
    end

    def prepend(klass, *args)
      remove(klass) if exists?(klass)
      entries.insert(0, Entry.new(klass, *args))
    end

    def insert_before(oldklass, newklass, *args)
      i = entries.index { |entry| entry.klass == newklass }
      new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
      i = entries.index { |entry| entry.klass == oldklass } || 0
      entries.insert(i, new_entry)
    end

    def insert_after(oldklass, newklass, *args)
      i = entries.index { |entry| entry.klass == newklass }
      new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
      i = entries.index { |entry| entry.klass == oldklass } || entries.count - 1
      entries.insert(i+1, new_entry)
    end

    def exists?(klass)
      any? { |entry| entry.klass == klass }
    end

    def retrieve
      map(&:make_new)
    end

    def clear
      entries.clear
    end

    def invoke(*args)
      chain = retrieve.dup
      traverse_chain = lambda do
        if chain.empty?
          yield
        else
          chain.pop.call(*args, &traverse_chain)
        end
      end
      traverse_chain.call
    end

    class Entry
      attr_reader :klass, :args

      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
