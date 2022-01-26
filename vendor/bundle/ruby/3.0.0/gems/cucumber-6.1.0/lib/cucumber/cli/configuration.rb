# frozen_string_literal: true

require 'logger'
require 'cucumber/cli/options'
require 'cucumber/cli/rerun_file'
require 'cucumber/constantize'
require 'cucumber'

module Cucumber
  module Cli
    class YmlLoadError < StandardError; end
    class ProfilesNotDefinedError < YmlLoadError; end
    class ProfileNotFound < StandardError; end

    class Configuration
      include Constantize

      attr_reader :out_stream

      def initialize(out_stream = STDOUT, error_stream = STDERR)
        @out_stream   = out_stream
        @error_stream = error_stream
        @options = Options.new(@out_stream, @error_stream, default_profile: 'default')
      end

      def parse!(args)
        @args = args
        @options.parse!(args)
        arrange_formats
        raise("You can't use both --strict and --wip") if strict.strict? && wip?
        set_environment_variables
      end

      def verbose?
        @options[:verbose]
      end

      def randomize?
        @options[:order] == 'random'
      end

      def seed
        Integer(@options[:seed] || rand(0xFFFF))
      end

      def strict
        @options[:strict]
      end

      def wip?
        @options[:wip]
      end

      def guess?
        @options[:guess]
      end

      def dry_run?
        @options[:dry_run]
      end

      def expand?
        @options[:expand]
      end

      def fail_fast?
        @options[:fail_fast]
      end

      def retry_attempts
        @options[:retry]
      end

      def snippet_type
        @options[:snippet_type] || :cucumber_expression
      end

      def log
        logger = Logger.new(@out_stream)
        logger.formatter = LogFormatter.new
        logger.level = Logger::INFO
        logger.level = Logger::DEBUG if verbose?
        logger
      end

      def tag_limits
        @options[:tag_limits]
      end

      def tag_expressions
        @options[:tag_expressions]
      end

      def name_regexps
        @options[:name_regexps]
      end

      def filters
        @options.filters
      end

      def formats
        @options[:formats]
      end

      def paths
        @options[:paths]
      end

      def to_hash
        Hash(@options).merge(out_stream: @out_stream, error_stream: @error_stream, seed: seed)
      end

      private

      class LogFormatter < ::Logger::Formatter
        def call(_severity, _time, _progname, msg)
          msg
        end
      end

      def set_environment_variables
        @options[:env_vars].each do |var, value|
          ENV[var] = value
        end
      end

      def arrange_formats
        add_default_formatter if needs_default_formatter?

        @options[:formats] = @options[:formats].sort_by do |f|
          f[2] == @out_stream ? -1 : 1
        end
        @options[:formats].uniq!
        @options.check_formatter_stream_conflicts
      end

      def add_default_formatter
        @options[:formats] << ['pretty', {}, @out_stream]
      end

      def needs_default_formatter?
        formatter_missing? || publish_only?
      end

      def formatter_missing?
        @options[:formats].empty?
      end

      def publish_only?
        @options[:formats]
          .uniq
          .map { |formatter, _, stream| [formatter, stream] }
          .uniq
          .reject { |formatter, stream| formatter == 'message' && stream != @out_stream }
          .empty?
      end
    end
  end
end
