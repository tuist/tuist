# frozen_string_literal: true

require 'yaml'
require 'cucumber/encoding'
require 'cucumber/platform'
require 'cucumber/runtime'
require 'cucumber/cli/main'
require 'cucumber/step_definitions'
require 'cucumber/term/ansicolor'

module Cucumber
  class << self
    attr_accessor :wants_to_quit, :use_legacy_autoloader

    def logger
      return @log if @log
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO
      @log
    end

    def logger=(logger)
      @log = logger
    end
  end
end
