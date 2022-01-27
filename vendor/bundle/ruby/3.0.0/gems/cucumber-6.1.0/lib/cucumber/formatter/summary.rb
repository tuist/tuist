# frozen_string_literal: true

require 'cucumber/formatter/io'
require 'cucumber/formatter/console'
require 'cucumber/formatter/console_counts'
require 'cucumber/formatter/console_issues'
require 'cucumber/core/test/result'
require 'cucumber/formatter/ast_lookup'

module Cucumber
  module Formatter
    # Summary formatter, outputting only feature / scenario titles
    class Summary
      include Io
      include Console

      def initialize(config)
        @config = config
        @io = ensure_io(config.out_stream, config.error_stream)
        @ast_lookup = AstLookup.new(config)
        @counts = ConsoleCounts.new(@config)
        @issues = ConsoleIssues.new(@config, @ast_lookup)
        @start_time = Time.now

        @config.on_event :test_case_started do |event|
          print_feature event.test_case
          print_test_case event.test_case
        end

        @config.on_event :test_case_finished do |event|
          print_result event.result
        end

        @config.on_event :test_run_finished do |_event|
          duration = Time.now - @start_time
          @io.puts
          print_statistics(duration, @config, @counts, @issues)
        end
      end

      private

      def gherkin_document(uri)
        @ast_lookup.gherkin_document(uri)
      end

      def print_feature(test_case)
        uri = test_case.location.file
        return if @current_feature_uri == uri
        feature_name = gherkin_document(uri).feature.name
        @io.puts unless @current_feature_uri.nil?
        @io.puts feature_name
        @current_feature_uri = uri
      end

      def print_test_case(test_case)
        @io.print "  #{test_case.name} "
      end

      def print_result(result)
        @io.puts format_string(result, result.to_sym)
      end
    end
  end
end
