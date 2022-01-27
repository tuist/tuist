module CLI
  module UI
    module Spinner
      class Async
        # Convenience method for +initialize+
        #
        def self.start(title)
          new(title)
        end

        # Initializes a new asynchronous spinner with no specific end.
        # Must call +.stop+ to end the spinner
        #
        # ==== Attributes
        #
        # * +title+ - Title of the spinner to use
        #
        # ==== Example Usage:
        #
        #   CLI::UI::Spinner::Async.new('Title')
        #
        def initialize(title)
          require 'thread'
          sg = CLI::UI::Spinner::SpinGroup.new
          @m = Mutex.new
          @cv = ConditionVariable.new
          sg.add(title) { @m.synchronize { @cv.wait(@m) } }
          @t = Thread.new { sg.wait }
        end

        # Stops an asynchronous spinner
        #
        def stop
          @m.synchronize { @cv.signal }
          @t.value
        end
      end
    end
  end
end
