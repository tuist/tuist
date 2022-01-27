# frozen_string_literal: true

require 'cucumber'
require 'cucumber/core/test/location'

module Cucumber
  class FileSpecs
    FILE_COLON_LINE_PATTERN = /^([\w\W]*?)(?::([\d:]+))?$/ #:nodoc:

    def initialize(file_specs)
      Cucumber.logger.debug("Features:\n")
      @file_specs = file_specs.map { |spec| FileSpec.new(spec) }
      Cucumber.logger.debug("\n")
    end

    def locations
      @file_specs.map(&:locations).flatten
    end

    def files
      @file_specs.map(&:file).uniq
    end

    class FileSpec
      def initialize(spec)
        @file, @lines = *FILE_COLON_LINE_PATTERN.match(spec).captures
        Cucumber.logger.debug("  * #{@file}\n")
        @lines = String(@lines).split(':').map { |line| Integer(line) }
      end

      attr_reader :file

      def locations
        return [Core::Test::Location.new(@file)] if @lines.empty?
        @lines.map { |line| Core::Test::Location.new(@file, line) }
      end
    end
  end
end
