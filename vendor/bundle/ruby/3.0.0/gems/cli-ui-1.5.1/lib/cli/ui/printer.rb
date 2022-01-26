require 'cli/ui'

module CLI
  module UI
    class Printer
      # Print a message to a stream with common utilities.
      # Allows overriding the color, encoding, and target stream.
      # By default, it formats the string using CLI:UI and rescues common stream errors.
      #
      # ==== Attributes
      #
      # * +msg+ - (required) the string to output. Can be frozen.
      #
      # ==== Options
      #
      # * +:frame_color+ - Override the frame color. Defaults to nil.
      # * +:to+ - Target stream, like $stdout or $stderr. Can be anything with a puts method. Defaults to $stdout.
      # * +:encoding+ - Force the output to be in a certain encoding. Defaults to UTF-8.
      # * +:format+ - Whether to format the string using CLI::UI.fmt. Defaults to true.
      # * +:graceful+ - Whether to gracefully ignore common I/O errors. Defaults to true.
      # * +:wrap+ - Whether to wrap text at word boundaries to terminal width. Defaults to true.
      #
      # ==== Returns
      # Returns whether the message was successfully printed,
      # which can be useful if +:graceful+ is set to true.
      #
      # ==== Example
      #
      #   CLI::UI::Printer.puts('{{x}} Ouch', to: $stderr)
      #
      def self.puts(
        msg,
        frame_color:
        nil,
        to:
        $stdout,
        encoding: Encoding::UTF_8,
        format: true,
        graceful: true,
        wrap: true
      )
        msg = (+msg).force_encoding(encoding) if encoding
        msg = CLI::UI.fmt(msg) if format
        msg = CLI::UI.wrap(msg) if wrap

        if frame_color
          CLI::UI::Frame.with_frame_color_override(frame_color) { to.puts(msg) }
        else
          to.puts(msg)
        end

        true
      rescue Errno::EIO, Errno::EPIPE, IOError => e
        raise(e) unless graceful
        false
      end
    end
  end
end
