module Minitest
  module Reporters
    # Simple reporter designed for RubyMate.
    class RubyMateReporter < BaseReporter
      include RelativePosition

      INFO_PADDING = 2

      def start
        super
        puts('Started with run options %s' % options[:args])
        puts
      end

      def record(test)
        super
        if test.skipped?
          print 'SKIP'
          print_test_with_time(test)
          puts
          puts
        elsif test.error?
          print 'ERROR'
          print_test_with_time(test)
          puts
          print_info(test.failure)
          puts
        elsif test.failure
          print 'FAIL'
          print_test_with_time(test)
          puts
          print_info(test.failure, false)
          puts
        end
      end

      def report
        super
        puts
        puts('Finished in %.5fs' % total_time)
        print('%d tests, %d assertions, ' % [count, assertions])
        print('%d failures, %d errors, ' % [failures, errors])
        print('%d skips' % skips)
        puts
      end

      private

      def print_test_with_time(test)
        print(" #{test.class}##{test.name} (%.2fs)" % test.time)
      end
    end
  end
end
