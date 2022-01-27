# Test results reporter for RubyMine IDE (http://www.jetbrains.com/ruby/) and
# TeamCity(http://www.jetbrains.com/teamcity/) Continuous Integration Server

begin
  require 'teamcity/runner_common'
  require 'teamcity/utils/service_message_factory'
  require 'teamcity/utils/runner_utils'
  require 'teamcity/utils/url_formatter'
rescue LoadError
  require "minitest/reporters/default_reporter"

  # delegate to default reporter
  module Minitest
    module Reporters
      class RubyMineReporter < DefaultReporter
        def initialize(options = {})
          super
          puts("====================================================================================================\n")
          puts("RubyMine reporter works only if it test was launched using RubyMine IDE or TeamCity CI server !!!\n")
          puts("====================================================================================================\n")
          puts("Using default results reporter...\n")
        end
      end
    end
  end
else
  module Minitest
    module Reporters
      class RubyMineReporter < BaseReporter
        include ANSI::Code

        include ::Rake::TeamCity::RunnerCommon
        include ::Rake::TeamCity::RunnerUtils
        include ::Rake::TeamCity::Utils::UrlFormatter

        def start
          super
          puts('Started with run options %s' % options[:args])
          puts

          # Setup test runner's MessageFactory
          set_message_factory(Rake::TeamCity::MessageFactory)
          log_test_reporter_attached

          # Report tests count:
          if ::Rake::TeamCity.is_in_idea_mode
            log(@message_factory.create_tests_count(total_count))
          elsif ::Rake::TeamCity.is_in_buildserver_mode
            log(@message_factory.create_progress_message("Starting.. (#{total_count} tests)"))
          end
        end

        def report
          super

          puts('Finished in %.5fs' % total_time)
          print('%d tests, %d assertions, ' % [count, assertions])
          print(red '%d failures, %d errors, ' % [failures, errors])
          print(yellow '%d skips' % skips)
          puts
        end

        def record(test)
          super
          unless test.passed?
            with_result(test) do |exception_msg, backtrace|
              if test.skipped?
                log(@message_factory.create_test_ignored(test.name, exception_msg, backtrace))
              elsif test.error?
                log(@message_factory.create_test_error(test.name, exception_msg, backtrace))
              else
                log(@message_factory.create_test_failed(test.name, exception_msg, backtrace))
              end
            end
          end
          log(@message_factory.create_test_finished(test.name, get_time_in_ms(test.time)))
        end

        alias_method :output, :io

        def before_suite(suite)
          fqn = suite.name
          log(@message_factory.create_suite_started(suite.name, location_from_ruby_qualified_name(fqn)))
        end

        def after_suite(suite)
          log(@message_factory.create_suite_finished(suite.name))
        end

        def before_test(test)
          super
          location = test.class.instance_method(test.name).source_location
          log(@message_factory.create_test_started(test.name, "file://#{location[0]}:#{location[1]}"))
        end

        #########
        def log(msg)
          output.flush
          output.puts("\n#{msg}")
          output.flush

          # returns:
          msg
        end

        def with_result(test)
          exception = test.failure
          msg = exception.nil? ? "" : "#{exception.class.name}: #{exception.message}"
          backtrace = exception.nil? ? "" : filter_backtrace(exception.backtrace).join("\n")

          yield(msg, backtrace)
        end
      end
    end
  end
end
