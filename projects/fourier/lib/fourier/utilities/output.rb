# frozen_string_literal: true
require "colorize"

module Fourier
  module Utilities
    class Output
      def self.section(message)
        STDERR.puts(message.cyan.bold)
      end

      def self.subsection(message)
        STDERR.puts(message.cyan)
      end

      def self.error(message)
        STDERR.puts(message.red.bold)
      end

      def self.warning(message)
        STDOUT.puts(message.yellow.bold)
      end

      def self.success(message)
        STDOUT.puts(message.green.bold)
      end
    end
  end
end
