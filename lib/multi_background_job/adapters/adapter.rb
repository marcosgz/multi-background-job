# frozen_string_literal: true

module MultiBackgroundJob
  module Adapters
    class Adapter
      # Push the worker job to the service
      # @param _worker [MultiBackgroundJob::Worker] An instance of background worker
      # @abstract Child classes should override this method
      def self.push(_worker)
        raise NotImplemented
      end

      # Sends the act state to the service
      # @param _worker [MultiBackgroundJob::Worker] An instance of background worker
      # @abstract Child classes should override this method
      def self.acknowledge(_worker)
        raise NotImplemented
      end

      # Coerces the raw payload into an instance of Worker
      # @param payload [Object] the object that should be coerced to a Worker
      # @options options [Hash] list of options that will be passed along to the Worker instance
      # @return [MultiBackgroundJob::Worker] and instance of MultiBackgroundJob::Worker
      # @abstract Child classes should override this method
      def self.coerce_to_worker(payload, **options)
        raise NotImplemented
      end
    end
  end
end
