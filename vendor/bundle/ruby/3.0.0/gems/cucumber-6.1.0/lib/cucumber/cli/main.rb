# frozen_string_literal: true

require 'optparse'
require 'cucumber'
require 'logger'
require 'cucumber/cli/configuration'

module Cucumber
  module Cli
    class Main
      class << self
        def execute(args)
          new(args).execute!
        end
      end

      def initialize(args, _ = nil, out = STDOUT, err = STDERR, kernel = Kernel)
        @args   = args
        @out    = out
        @err    = err
        @kernel = kernel
      end

      def execute!(existing_runtime = nil)
        trap_interrupt

        runtime = runtime(existing_runtime)

        runtime.run!
        if Cucumber.wants_to_quit
          exit_unable_to_finish
        elsif runtime.failure?
          exit_tests_failed
        else
          exit_ok
        end
      rescue SystemExit => e
        @kernel.exit(e.status)
      rescue FileNotFoundException => e
        @err.puts(e.message)
        @err.puts("Couldn't open #{e.path}")
        exit_unable_to_finish
      rescue FeatureFolderNotFoundException => e
        @err.puts(e.message + '. You can use `cucumber --init` to get started.')
        exit_unable_to_finish
      rescue ProfilesNotDefinedError, YmlLoadError, ProfileNotFound => e
        @err.puts(e.message)
        exit_unable_to_finish
      rescue Errno::EACCES, Errno::ENOENT => e
        @err.puts("#{e.message} (#{e.class})")
        exit_unable_to_finish
      rescue Exception => e # rubocop:disable Lint/RescueException
        @err.puts("#{e.message} (#{e.class})")
        @err.puts(e.backtrace.join("\n"))
        exit_unable_to_finish
      end

      def configuration
        @configuration ||= Configuration.new(@out, @err).tap do |configuration|
          configuration.parse!(@args)
          Cucumber.logger = configuration.log
        end
      end

      private

      def exit_ok
        @kernel.exit 0
      end

      def exit_tests_failed
        @kernel.exit 1
      end

      def exit_unable_to_finish
        @kernel.exit 2
      end

      # stops the program immediately, without running at_exit blocks
      def exit_unable_to_finish!
        @kernel.exit! 2
      end

      def trap_interrupt
        trap('INT') do
          exit_unable_to_finish! if Cucumber.wants_to_quit
          Cucumber.wants_to_quit = true
          STDERR.puts "\nExiting... Interrupt again to exit immediately."
          exit_unable_to_finish
        end
      end

      def runtime(existing_runtime)
        return Runtime.new(configuration) unless existing_runtime
        existing_runtime.configure(configuration)
        existing_runtime
      end
    end
  end
end
