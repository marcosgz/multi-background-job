# frozen_string_literal: true

module MultiBackgroundJob
  class Error < StandardError
  end

  class InvalidConfig < Error
  end

  class NotDefinedWorker < Error
    def initialize(worker_class)
      @worker_class = worker_class
    end

    def message
      format(
        "The %<worker>p is not defined and the MultiBackgroundJob is configured to work on strict mode.\n" +
        "it's highly recommended to include this worker class to the list of known workers.\n" +
        "Example: `MultiBackgroundJob.configure { |config| config.workers => { %<worker>p => {} } }`\n" +
        'Another option is to set config.strict = false',
        worker: @worker_class,
      )
    end
  end
end
