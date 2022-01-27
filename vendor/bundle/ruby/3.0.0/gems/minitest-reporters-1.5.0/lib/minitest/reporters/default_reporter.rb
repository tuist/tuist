module Minitest
  module Reporters
    # A reporter identical to the standard Minitest reporter except with more
    # colors.
    #
    # Based upon Ryan Davis of Seattle.rb's Minitest (MIT License).
    #
    # @see https://github.com/seattlerb/minitest Minitest

    class DefaultReporter < BaseReporter
      include ANSI::Code
      include RelativePosition

      def initialize(options = {})
        super
        @detailed_skip = options.fetch(:detailed_skip, true)
        @slow_count = options.fetch(:slow_count, 0)
        @slow_suite_count = options.fetch(:slow_suite_count, 0)
        @suite_times = []
        @suite_start_times = {}
        @fast_fail = options.fetch(:fast_fail, false)
        @show_test_location = options.fetch(:location, false)
        @options = options
      end

      def start
        super
        on_start
      end

      def on_start
        puts
        puts("# Running tests with run options %s:" % options[:args])
        puts
      end

      def before_test(test)
        super
        print "\n#{test.class}##{test.name} " if options[:verbose]
      end

      def before_suite(suite)
        @suite_start_times[suite] = Minitest::Reporters.clock_time
        super
      end

      def after_suite(suite)
        super
        duration = suite_duration(suite)
        @suite_times << [suite.name, duration]
      end

      def record(test)
        super

        on_record(test)
      end

      def on_record(test)
        print "#{"%.2f" % test.time} = " if options[:verbose]

        # Print the pass/skip/fail mark
        print(if test.passed?
          record_pass(test)
        elsif test.skipped?
          record_skip(test)
        elsif test.failure
          record_failure(test)
        end)

        # Print fast_fail information
        if @fast_fail && (test.skipped? || test.failure)
          print_failure(test)
        end
      end

      def record_pass(record)
        green(record.result_code)
      end

      def record_skip(record)
        yellow(record.result_code)
      end

      def record_failure(record)
        red(record.result_code)
      end

      def report
        super
        on_report
      end

      def on_report
        status_line = "Finished tests in %.6fs, %.4f tests/s, %.4f assertions/s." %
          [total_time, count / total_time, assertions / total_time]

        puts
        puts
        puts colored_for(suite_result, status_line)
        puts

        unless @fast_fail
          tests.reject(&:passed?).each do |test|
            print_failure(test)
          end
        end

        if @slow_count > 0
          slow_tests = tests.sort_by(&:time).reverse.take(@slow_count)

          puts
          puts "Slowest tests:"
          puts

          slow_tests.each do |test|
            puts "%.6fs %s#%s" % [test.time, test.name, test_class(test)]
          end
        end

        if @slow_suite_count > 0
          slow_suites = @suite_times.sort_by { |x| x[1] }.reverse.take(@slow_suite_count)

          puts
          puts "Slowest test classes:"
          puts

          slow_suites.each do |slow_suite|
            puts "%.6fs %s" % [slow_suite[1], slow_suite[0]]
          end
        end

        puts
        print colored_for(suite_result, result_line)
        puts
      end

      alias to_s report

      def print_failure(test)
        message = message_for(test)
        unless message.nil? || message.strip == ''
          puts
          puts colored_for(result(test), message)
          if @show_test_location
            location = get_source_location(test)
            puts "\n\n#{relative_path(location[0])}:#{location[1]}"
          end

        end
      end

      private

      def relative_path(path)
        Pathname.new(path).relative_path_from(Pathname.new(Dir.getwd))
      end
      
      def get_source_location(result)
        if result.respond_to? :klass
          result.source_location
        else
          result.method(result.name).source_location
        end
      end

      def color?
        return @color if defined?(@color)
        @color = @options.fetch(:color) do
          io.tty? && (
            ENV["TERM"] =~ /^screen|color/ ||
            ENV["EMACS"] == "t"
          )
        end
      end

      def green(string)
        color? ? ANSI::Code.green(string) : string
      end

      def yellow(string)
        color? ? ANSI::Code.yellow(string) : string
      end

      def red(string)
        color? ? ANSI::Code.red(string) : string
      end

      def colored_for(result, string)
        case result
        when :fail, :error; red(string)
        when :skip; yellow(string)
        else green(string)
        end
      end

      def suite_result
        case
        when failures > 0; :fail
        when errors > 0; :error
        when skips > 0; :skip
        else :pass
        end
      end

      def location(exception)
        last_before_assertion = ''
        exception.backtrace.reverse_each do |s|
          break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/
          last_before_assertion = s
        end

        last_before_assertion.sub(/:in .*$/, '')
      end

      def message_for(test)
        e = test.failure

        if test.skipped?
          if @detailed_skip
            "Skipped:\n#{test_class(test)}##{test.name} [#{location(e)}]:\n#{e.message}"
          end
        elsif test.error?
          "Error:\n#{test_class(test)}##{test.name}:\n#{e.message}"
        else
          "Failure:\n#{test_class(test)}##{test.name} [#{test.failure.location}]\n#{e.class}: #{e.message}"
        end
      end

      def result_line
        '%d tests, %d assertions, %d failures, %d errors, %d skips' %
          [count, assertions, failures, errors, skips]
      end

      def suite_duration(suite)
        start_time = @suite_start_times.delete(suite)
        if start_time.nil?
          0
        else
          Minitest::Reporters.clock_time - start_time
        end
      end
    end
  end
end
