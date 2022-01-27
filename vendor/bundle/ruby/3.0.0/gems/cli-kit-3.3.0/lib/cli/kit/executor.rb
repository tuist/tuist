require 'cli/kit'
require 'English'
require 'fileutils'

module CLI
  module Kit
    class Executor
      def initialize(log_file:)
        FileUtils.mkpath(File.dirname(log_file))
        @log_file = log_file
      end

      def call(command, command_name, args)
        with_traps do
          with_logging do |id|
            begin
              command.call(args, command_name)
            rescue => e
              begin
                $stderr.puts "This command ran with ID: #{id}"
                $stderr.puts "Please include this information in any issues/report along with relevant logs"
              rescue SystemCallError
                # Outputting to stderr is best-effort.  Avoid raising another error when outputting debug info so that
                # we can detect and log the original error, which may even be the source of this error.
                nil
              end
              raise e
            end
          end
        end
      end

      private

      def with_logging(&block)
        return yield unless @log_file
        CLI::UI.log_output_to(@log_file) do
          CLI::UI::StdoutRouter.with_id(on_streams: [CLI::UI::StdoutRouter.duplicate_output_to]) do |id|
            block.call(id)
          end
        end
      end

      def with_traps
        twrap('QUIT', method(:quit_handler)) do
          twrap('INFO', method(:info_handler)) do
            yield
          end
        end
      end

      def twrap(signal, handler)
        return yield unless Signal.list.key?(signal)

        begin
          prev_handler = trap(signal, handler)
          yield
        ensure
          trap(signal, prev_handler)
        end
      end

      def quit_handler(_sig)
        z = caller
        CLI::UI.raw do
          $stderr.puts('SIGQUIT: quit')
          $stderr.puts(z)
        end
        exit(CLI::Kit::EXIT_FAILURE_BUT_NOT_BUG)
      end

      def info_handler(_sig)
        z = caller
        CLI::UI.raw do
          $stderr.puts('SIGINFO:')
          $stderr.puts(z)
        end
      end
    end
  end
end
