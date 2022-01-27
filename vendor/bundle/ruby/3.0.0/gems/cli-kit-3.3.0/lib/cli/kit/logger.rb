require 'logger'
require 'fileutils'

module CLI
  module Kit
    class Logger
      MAX_LOG_SIZE = 5 * 1024 * 1000 # 5MB
      MAX_NUM_LOGS = 10

      # Constructor for CLI::Kit::Logger
      #
      # @param debug_log_file [String] path to the file where debug logs should be stored
      def initialize(debug_log_file:)
        FileUtils.mkpath(File.dirname(debug_log_file))
        @debug_logger = ::Logger.new(debug_log_file, MAX_NUM_LOGS, MAX_LOG_SIZE)
      end

      # Functionally equivalent to Logger#info
      # Also logs to the debug file, taking into account CLI::UI::StdoutRouter.current_id
      #
      # @param msg [String] the message to log
      # @param debug [Boolean] determines if the debug logger will receive the log (default true)
      def info(msg, debug: true)
        $stdout.puts CLI::UI.fmt(msg)
        @debug_logger.info(format_debug(msg)) if debug
      end

      # Functionally equivalent to Logger#warn
      # Also logs to the debug file, taking into account CLI::UI::StdoutRouter.current_id
      #
      # @param msg [String] the message to log
      # @param debug [Boolean] determines if the debug logger will receive the log (default true)
      def warn(msg, debug: true)
        $stdout.puts CLI::UI.fmt("{{yellow:#{msg}}}")
        @debug_logger.warn(format_debug(msg)) if debug
      end

      # Functionally equivalent to Logger#error
      # Also logs to the debug file, taking into account CLI::UI::StdoutRouter.current_id
      #
      # @param msg [String] the message to log
      # @param debug [Boolean] determines if the debug logger will receive the log (default true)
      def error(msg, debug: true)
        $stderr.puts CLI::UI.fmt("{{red:#{msg}}}")
        @debug_logger.error(format_debug(msg)) if debug
      end

      # Functionally equivalent to Logger#fatal
      # Also logs to the debug file, taking into account CLI::UI::StdoutRouter.current_id
      #
      # @param msg [String] the message to log
      # @param debug [Boolean] determines if the debug logger will receive the log (default true)
      def fatal(msg, debug: true)
        $stderr.puts CLI::UI.fmt("{{red:{{bold:Fatal:}} #{msg}}}")
        @debug_logger.fatal(format_debug(msg)) if debug
      end

      # Similar to Logger#debug, however will not output to STDOUT unless DEBUG env var is set
      # Logs to the debug file, taking into account CLI::UI::StdoutRouter.current_id
      #
      # @param msg [String] the message to log
      def debug(msg)
        $stdout.puts CLI::UI.fmt(msg) if ENV['DEBUG']
        @debug_logger.debug(format_debug(msg))
      end

      private

      def format_debug(msg)
        msg = CLI::UI.fmt(msg)
        return msg unless CLI::UI::StdoutRouter.current_id
        "[#{CLI::UI::StdoutRouter.current_id[:id]}] #{msg}"
      end
    end
  end
end
