# frozen_string_literal: true

require "colorize"

module Fourier
  module Utilities
    class Output
      def self.section(message)
        $stderr.puts(message.cyan.bold)
      end

      def self.subsection(message)
        $stderr.puts(message.cyan)
      end

      def self.error(message)
        $stderr.puts(message.red.bold)
      end

      def self.warning(message)
        $stdout.puts(message.yellow.bold)
      end

      def self.success(message)
        $stdout.puts(message.green.bold)
      end
    end
  end
end
