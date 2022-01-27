require 'cli/ui'
require 'stringio'

module CLI
  module UI
    module StdoutRouter
      class << self
        attr_accessor :duplicate_output_to
      end

      class Writer
        def initialize(stream, name)
          @stream = stream
          @name = name
        end

        def write(*args)
          args = args.map do |str|
            if auto_frame_inset?
              str = str.dup # unfreeze
              str = str.force_encoding(Encoding::UTF_8)
              apply_line_prefix(str, CLI::UI::Frame.prefix)
            else
              @pending_newline = false
              str
            end
          end

          # hook return of false suppresses output.
          if (hook = Thread.current[:cliui_output_hook])
            return if hook.call(args.map(&:to_s).join, @name) == false
          end

          @stream.write_without_cli_ui(*prepend_id(@stream, args))
          if (dup = StdoutRouter.duplicate_output_to)
            dup.write(*prepend_id(dup, args))
          end
        end

        private

        def prepend_id(stream, args)
          return args unless prepend_id_for_stream(stream)
          args.map do |a|
            next a if a.chomp.empty? # allow new lines to be new lines
            "[#{Thread.current[:cliui_output_id][:id]}] #{a}"
          end
        end

        def prepend_id_for_stream(stream)
          return false unless Thread.current[:cliui_output_id]
          return true if Thread.current[:cliui_output_id][:streams].include?(stream)
          false
        end

        def auto_frame_inset?
          !Thread.current[:no_cliui_frame_inset]
        end

        def apply_line_prefix(str, prefix)
          return '' if str.empty?
          prefixed = +''
          str.force_encoding(Encoding::UTF_8).lines.each do |line|
            if @pending_newline
              prefixed << line
              @pending_newline = false
            else
              prefixed << prefix << line
            end
          end
          @pending_newline = !str.end_with?("\n")
          prefixed
        end
      end

      class Capture
        @m = Mutex.new
        @active_captures = 0
        @saved_stdin = nil

        def self.with_stdin_masked
          @m.synchronize do
            if @active_captures.zero?
              @saved_stdin = $stdin
              $stdin, w = IO.pipe
              $stdin.close
              w.close
            end
            @active_captures += 1
          end

          yield
        ensure
          @m.synchronize do
            @active_captures -= 1
            if @active_captures.zero?
              $stdin = @saved_stdin
            end
          end
        end

        def initialize(*block_args, with_frame_inset: true, &block)
          @with_frame_inset = with_frame_inset
          @block_args = block_args
          @block = block
        end

        attr_reader :stdout, :stderr

        def run
          require 'stringio'

          StdoutRouter.assert_enabled!

          out = StringIO.new
          err = StringIO.new

          prev_frame_inset = Thread.current[:no_cliui_frame_inset]
          prev_hook = Thread.current[:cliui_output_hook]

          if Thread.current.respond_to?(:report_on_exception)
            Thread.current.report_on_exception = false
          end

          self.class.with_stdin_masked do
            Thread.current[:no_cliui_frame_inset] = !@with_frame_inset
            Thread.current[:cliui_output_hook] = ->(data, stream) do
              case stream
              when :stdout then out.write(data)
              when :stderr then err.write(data)
              else raise
              end
              false # suppress writing to terminal
            end

            begin
              @block.call(*@block_args)
            ensure
              @stdout = out.string
              @stderr = err.string
            end
          end
        ensure
          Thread.current[:cliui_output_hook] = prev_hook
          Thread.current[:no_cliui_frame_inset] = prev_frame_inset
        end
      end

      class << self
        WRITE_WITHOUT_CLI_UI = :write_without_cli_ui

        NotEnabled = Class.new(StandardError)

        def with_id(on_streams:)
          unless on_streams.is_a?(Array) && on_streams.all? { |s| s.respond_to?(:write) }
            raise ArgumentError, <<~EOF
            on_streams must be an array of objects that respond to `write`
            These do not respond to write
            #{on_streams.reject { |s| s.respond_to?(:write) }.map.with_index { |s| s.class.to_s }.join("\n")}
            EOF
          end

          require 'securerandom'
          id = format('%05d', rand(10**5))
          Thread.current[:cliui_output_id] = {
            id: id,
            streams: on_streams,
          }
          yield(id)
        ensure
          Thread.current[:cliui_output_id] = nil
        end

        def current_id
          Thread.current[:cliui_output_id]
        end

        def assert_enabled!
          raise NotEnabled unless enabled?
        end

        def with_enabled
          enable
          yield
        ensure
          disable
        end

        # TODO: remove this
        def ensure_activated
          enable unless enabled?
        end

        def enable
          return false if enabled?($stdout) || enabled?($stderr)
          activate($stdout, :stdout)
          activate($stderr, :stderr)
          true
        end

        def enabled?(stream = $stdout)
          stream.respond_to?(WRITE_WITHOUT_CLI_UI)
        end

        def disable
          return false unless enabled?($stdout) && enabled?($stderr)
          deactivate($stdout)
          deactivate($stderr)
          true
        end

        private

        def deactivate(stream)
          sc = stream.singleton_class
          sc.send(:remove_method, :write)
          sc.send(:alias_method, :write, WRITE_WITHOUT_CLI_UI)
        end

        def activate(stream, streamname)
          writer = StdoutRouter::Writer.new(stream, streamname)

          raise if stream.respond_to?(WRITE_WITHOUT_CLI_UI)
          stream.singleton_class.send(:alias_method, WRITE_WITHOUT_CLI_UI, :write)
          stream.define_singleton_method(:write) do |*args|
            writer.write(*args)
          end
        end
      end
    end
  end
end
