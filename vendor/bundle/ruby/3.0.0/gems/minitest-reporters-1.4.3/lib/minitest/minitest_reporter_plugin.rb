module Minitest
  module Reporters
    class DelegateReporter < Minitest::AbstractReporter
      def initialize(reporters, options = {})
        @reporters = reporters
        @options = options
        @all_reporters = nil
      end

      def io
        all_reporters.first.io unless all_reporters.empty?
        @options[:io]
      end

      def start
        all_reporters.each(&:start)
      end

      def prerecord(klass, name)
        all_reporters.each do |reporter|
          reporter.prerecord klass, name
        end
      end

      def record(result)
        all_reporters.each do |reporter|
          reporter.record result
        end
      end

      def report
        all_reporters.each(&:report)
      end

      def passed?
        all_reporters.all?(&:passed?)
      end

      private

      # stolen from minitest self.run
      def total_count(options)
        filter = options[:filter] || '/./'
        filter = Regexp.new $1 if filter =~ /\/(.*)\//

        Minitest::Runnable.runnables.map { |runnable|
          runnable.runnable_methods.find_all { |m|
            filter === m || filter === "#{runnable}##{m}"
          }.size
        }.inject(:+)
      end

      def all_reporters
        @all_reporters ||= init_all_reporters
      end

      def init_all_reporters
        return @reporters unless defined?(Minitest::Reporters.reporters) && Minitest::Reporters.reporters
        (Minitest::Reporters.reporters + guard_reporter(@reporters)).each do |reporter|
          reporter.io = @options[:io]
          if reporter.respond_to?(:add_defaults)
            reporter.add_defaults(@options.merge(:total_count => total_count(@options)))
          end
        end
      end

      def guard_reporter(reporters)
        guards = Array(reporters.detect { |r| r.class.name == "Guard::Minitest::Reporter" })
        return guards unless ENV['RM_INFO']

        warn 'RM_INFO is set thus guard reporter has been dropped' unless guards.empty?
        []
      end
    end
  end

  class << self
    def plugin_minitest_reporter_init(options)
      reporter.reporters = [Minitest::Reporters::DelegateReporter.new(reporter.reporters, options)]
    end
  end
end
