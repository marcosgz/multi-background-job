# frizen_string_literal: true

module MultiBackgroundJob
  module Workers
    module SharedClassMethods
      def perform_async(*args)
        build_worker.with_args(*args).push
      end

      def perform_in(interval, *args)
        build_worker.with_args(*args).at(interval).push
      end
      alias_method :perform_at, :perform_in

      protected

      def service_worker_options
        {}
      end

      def build_worker
        MultiBackgroundJob[self.name, **service_worker_options.merge(bg_worker_options)]
      end
    end
  end
end
