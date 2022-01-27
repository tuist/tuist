require 'builder'
require 'fileutils'
require 'erb'

module Minitest
  module Reporters
    # A reporter for generating HTML test reports
    # This is recommended to be used with a CI server, where the report is kept as an artifact and is accessible via
    # a shared link
    #
    # The reporter sorts the results alphabetically and then by results
    # so that failing and skipped tests are at the top.
    #
    # When using Minitest Specs, the number prefix is dropped from the name of the test so that it reads well
    #
    # On each test run all files in the reports directory are deleted, this prevents a build up of old reports
    #
    # The report is generated using ERB. A custom ERB template can be provided but it is not required
    # The default ERB template uses JQuery and Bootstrap, both of these are included by referencing the CDN sites
    class HtmlReporter < BaseReporter
      # The title of the report
      attr_reader :title

      # The number of tests that passed
      def passes
        count - failures - errors - skips
      end

      # The percentage of tests that passed, calculated in a way that avoids rounding errors
      def percent_passes
        100 - percent_skipps - percent_errors_failures
      end

      # The percentage of tests that were skipped
      def percent_skipps
        (skips / count.to_f * 100).to_i
      end

      # The percentage of tests that failed
      def percent_errors_failures
        ((errors + failures) / count.to_f * 100).to_i
      end

      # Trims off the number prefix on test names when using Minitest Specs
      def friendly_name(test)
        groups = test.name.scan(/(test_\d+_)(.*)/i)
        return test.name if groups.empty?
        "it #{groups[0][1]}"
      end

      # The constructor takes a hash, and uses the following keys:
      # :title - the title that will be used in the report, defaults to 'Test Results'
      # :reports_dir - the directory the reports should be written to, defaults to 'test/html_reports'
      # :erb_template - the path to a custom ERB template, defaults to the supplied ERB template
      # :mode - Useful for debugging, :terse suppresses errors and is the default, :verbose lets errors bubble up
      # :output_filename - the report's filename, defaults to 'index.html'
      def initialize(args = {})
        super({})

        defaults = {
          :title           => 'Test Results',
          :erb_template    => "#{File.dirname(__FILE__)}/../templates/index.html.erb",
          :reports_dir     => 'test/html_reports',
          :mode            => :safe,
          :output_filename => 'index.html',
        }

        settings = defaults.merge(args)

        @mode = settings[:mode]
        @title = settings[:title]
        @erb_template = settings[:erb_template]
        @output_filename = settings[:output_filename]
        reports_dir = settings[:reports_dir]

        @reports_path = File.absolute_path(reports_dir)
      end

      def start
        super

        puts "Emptying #{@reports_path}"
        FileUtils.mkdir_p(@reports_path)
        File.delete(html_file) if File.exist?(html_file)
      end

      # Called by the framework to generate the report
      def report
        super

        begin
          puts "Writing HTML reports to #{@reports_path}"
          erb_str = File.read(@erb_template)
          renderer = ERB.new(erb_str)

          tests_by_suites = tests.group_by { |test| test_class(test) } # taken from the JUnit reporter

          suites = tests_by_suites.map do |suite, tests|
            suite_summary = summarize_suite(suite, tests)
            suite_summary[:tests] = tests.sort { |a, b| compare_tests(a, b) }
            suite_summary
          end

          suites.sort! { |a, b| compare_suites(a, b) }

          result = renderer.result(binding)
          File.open(html_file, 'w') do |f|
            f.write(result)
          end

        # rubocop:disable Lint/RescueException
        rescue Exception => e
          puts 'There was an error writing the HTML report'
          puts 'This may have been caused by cancelling the test run'
          puts 'Use mode => :verbose in the HTML reporters constructor to see more detail' if @mode == :terse
          puts 'Use mode => :terse in the HTML reporters constructor to see less detail' if @mode != :terse
          raise e if @mode != :terse
        end
        # rubocop:enable Lint/RescueException
      end

      private

      def html_file
        "#{@reports_path}/#{@output_filename}"
      end

      def compare_suites_by_name(suite_a, suite_b)
        suite_a[:name] <=> suite_b[:name]
      end

      def compare_tests_by_name(test_a, test_b)
        friendly_name(test_a) <=> friendly_name(test_b)
      end

      # Test suites are first ordered by evaluating the results of the tests, then by test suite name
      # Test suites which have failing tests are given highest order
      # Tests suites which have skipped tests are given second highest priority
      def compare_suites(suite_a, suite_b)
        return compare_suites_by_name(suite_a, suite_b) if suite_a[:has_errors_or_failures] && suite_b[:has_errors_or_failures]
        return -1 if suite_a[:has_errors_or_failures] && !suite_b[:has_errors_or_failures]
        return 1 if !suite_a[:has_errors_or_failures] && suite_b[:has_errors_or_failures]

        return compare_suites_by_name(suite_a, suite_b) if suite_a[:has_skipps] && suite_b[:has_skipps]
        return -1 if suite_a[:has_skipps] && !suite_b[:has_skipps]
        return 1 if !suite_a[:has_skipps] && suite_b[:has_skipps]

        compare_suites_by_name(suite_a, suite_b)
      end

      # Tests are first ordered by evaluating the results of the tests, then by tests names
      # Tess which fail are given highest order
      # Tests which are skipped are given second highest priority
      def compare_tests(test_a, test_b)
        return compare_tests_by_name(test_a, test_b) if test_fail_or_error?(test_a) && test_fail_or_error?(test_b)

        return -1 if test_fail_or_error?(test_a) && !test_fail_or_error?(test_b)
        return 1 if !test_fail_or_error?(test_a) && test_fail_or_error?(test_b)

        return compare_tests_by_name(test_a, test_b) if test_a.skipped? && test_b.skipped?
        return -1 if test_a.skipped? && !test_b.skipped?
        return 1 if !test_a.skipped? && test_b.skipped?

        compare_tests_by_name(test_a, test_b)
      end

      def test_fail_or_error?(test)
        test.error? || test.failure
      end

      # based on analyze_suite from the JUnit reporter
      def summarize_suite(suite, tests)
        summary = Hash.new(0)
        summary[:name] = suite.to_s
        tests.each do |test|
          summary[:"#{result(test)}_count"] += 1
          summary[:assertion_count] += test.assertions
          summary[:test_count] += 1
          summary[:time] += test.time
        end
        summary[:has_errors_or_failures] = (summary[:fail_count] + summary[:error_count]) > 0
        summary[:has_skipps] = summary[:skip_count] > 0
        summary
      end

      # based on message_for(test) from the JUnit reporter
      def message_for(test)
        suite = test.class
        name = test.name
        e = test.failure

        if test.passed?
          nil
        elsif test.skipped?
          "Skipped:\n#{name}(#{suite}) [#{location(e)}]:\n#{e.message}\n"
        elsif test.failure
          "Failure:\n#{name}(#{suite}) [#{location(e)}]:\n#{e.message}\n"
        elsif test.error?
          "Error:\n#{name}(#{suite}):\n#{e.message}"
        end
      end

      # taken from the JUnit reporter
      def location(exception)
        last_before_assertion = ''
        exception.backtrace.reverse_each do |s|
          break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/
          last_before_assertion = s
        end
        last_before_assertion.sub(/:in .*$/, '')
      end

      def total_time_to_hms
        return ('%.2fs' % total_time) if total_time < 1

        hours = (total_time / (60 * 60)).round
        minutes = ((total_time / 60) % 60).round.to_s.rjust(2, '0')
        seconds = (total_time % 60).round.to_s.rjust(2, '0')

        "#{hours}h#{minutes}m#{seconds}s"
      end
    end
  end
end
