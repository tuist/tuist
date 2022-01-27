# frozen_string_literal: true

require 'cucumber/core/events'

module Cucumber
  module Events
    # Event fired when a Test::Case is ready to be ran (matching has been done, hooks added etc)
    class TestCaseReady < Core::Event.new(:test_case)
      attr_reader :test_case
    end
  end
end
