# frozen_string_literal: true

require 'cucumber/formatter/io'

module Cucumber
  module Formatter
    class Rerun
      include Formatter::Io

      def initialize(config)
        @io = ensure_io(config.out_stream, config.error_stream)
        @config = config
        @failures = {}
        config.on_event :test_case_finished do |event|
          test_case, result = *event.attributes
          if @config.strict.strict?(:flaky)
            next if result.ok?(@config.strict)
            add_to_failures(test_case)
          else
            unless @latest_failed_test_case.nil?
              if @latest_failed_test_case != test_case
                add_to_failures(@latest_failed_test_case)
                @latest_failed_test_case = nil
              elsif result.ok?(@config.strict)
                @latest_failed_test_case = nil
              end
            end
            @latest_failed_test_case = test_case unless result.ok?(@config.strict)
          end
        end
        config.on_event :test_run_finished do
          add_to_failures(@latest_failed_test_case) unless @latest_failed_test_case.nil?
          next if @failures.empty?
          @io.print file_failures.join("\n")
        end
      end

      private

      def file_failures
        @failures.map { |file, lines| [file, lines].join(':') }
      end

      def add_to_failures(test_case)
        location = test_case.location
        @failures[location.file] ||= []
        @failures[location.file] << location.lines.max unless @failures[location.file].include?(location.lines.max)
      end
    end
  end
end
