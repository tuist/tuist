module Cucumber
  module Formatter
    class URLReporter
      def initialize(io)
        @io = io
      end

      def report(banner)
        @io.puts(banner)
      end
    end

    class NoReporter
      def report(banner); end
    end
  end
end
