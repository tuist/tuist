require 'ruby-progressbar'

module Minitest
  module Reporters
    # Fuubar-like reporter with a progress bar.
    #
    # Based upon Jeff Kreefmeijer's Fuubar (MIT License) and paydro's
    # monkey-patch.
    #
    # @see https://github.com/jeffkreeftmeijer/fuubar Fuubar
    # @see https://gist.github.com/356945 paydro's monkey-patch
    class ProgressReporter < BaseReporter
      include RelativePosition
      include ANSI::Code

      PROGRESS_MARK = '='.freeze

      def initialize(options = {})
        super
        @detailed_skip = options.fetch(:detailed_skip, true)

        @progress = ProgressBar.create(
          total:          total_count,
          starting_at:    count,
          progress_mark:  green(PROGRESS_MARK),
          remainder_mark: ' ',
          format:         options.fetch(:format, '  %C/%c: [%B] %p%% %a, %e'),
          autostart:      false
        )
      end

      def start
        super
        puts('Started with run options %s' % options[:args])
        puts
        @progress.start
        @progress.total = total_count
        show
      end

      def before_test(test)
        super
        if options[:verbose]
          puts
          puts("\n%s#%s" % [test_class(test), test.name])
        end
      end

      def record(test)
        super
        return if test.skipped? && !@detailed_skip
        if test.failure
          print "\e[0m\e[1000D\e[K"
          print_colored_status(test)
          print_test_with_time(test)
          puts
          print_info(test.failure, test.error?)
          puts
        end

        if test.skipped? && color != "red"
          self.color = "yellow"
        elsif test.failure
          self.color = "red"
        end

        show
      end

      def report
        super
        @progress.finish

        puts
        puts('Finished in %.5fs' % total_time)
        print('%d tests, %d assertions, ' % [count, assertions])
        color = failures.zero? && errors.zero? ? :green : :red
        print(send(color) { '%d failures, %d errors, ' } % [failures, errors])
        print(yellow { '%d skips' } % skips)
        puts
      end

      private

      def show
        @progress.increment unless count == 0
      end

      def print_test_with_time(test)
        print(" %s#%s (%.2fs)" % [test_class(test), test.name, total_time])
      end

      def color
        @color ||= "green"
      end

      def color=(color)
        @color = color
        @progress.progress_mark = send(color, PROGRESS_MARK)
      end
    end
  end
end
