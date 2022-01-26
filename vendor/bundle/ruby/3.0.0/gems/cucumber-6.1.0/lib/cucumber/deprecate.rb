# frozen_string_literal: true

require 'cucumber/platform'
require 'cucumber/gherkin/formatter/ansi_escapes'

module Cucumber
  module Deprecate
    class AnsiString
      include Cucumber::Gherkin::Formatter::AnsiEscapes

      def self.failure_message(message)
        AnsiString.new.failure_message(message)
      end

      def failure_message(message)
        failed + message + reset
      end
    end

    class CliOption
      def self.deprecate(stream, option, message, remove_after_version)
        return if stream.nil?
        stream.puts(
          AnsiString.failure_message(
            "\nWARNING: #{option} is deprecated" \
            " and will be removed after version #{remove_after_version}.\n#{message}.\n"
          )
        )
      end
    end

    module ForUsers
      def self.call(message, method, remove_after_version)
        STDERR.puts AnsiString.failure_message(
          "\nWARNING: ##{method} is deprecated" \
          " and will be removed after version #{remove_after_version}. #{message}.\n" \
          "(Called from #{caller(3..3).first})"
        )
      end
    end

    module ForDevelopers
      def self.call(_message, _method, remove_after_version)
        raise "This method is due for removal after version #{remove_after_version}" if Cucumber::VERSION >= remove_after_version
      end
    end

    STRATEGY = $PROGRAM_NAME =~ /rspec$/ ? ForDevelopers : ForUsers
  end

  def self.deprecate(*args)
    Deprecate::STRATEGY.call(*args)
  end
end
