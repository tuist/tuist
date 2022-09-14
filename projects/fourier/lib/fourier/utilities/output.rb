# frozen_string_literal: true

require "colorize"

module Fourier
  module Utilities
    class Output
      class << self
        def section(message)
          $stderr.puts(message.cyan.bold)
        end

        def subsection(message)
          $stderr.puts(message.cyan)
        end

        def error(message)
          $stderr.puts(message.red.bold)
        end

        def warning(message)
          $stdout.puts(message.yellow.bold)
        end

        def success(message)
          $stdout.puts(message.green.bold)
        end
      end
    end
  end
end
