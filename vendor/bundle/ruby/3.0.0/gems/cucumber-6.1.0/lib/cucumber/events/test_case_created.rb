# frozen_string_literal: true

require 'cucumber/core/events'

module Cucumber
  module Events
    # Event fired when a Test::Case is created from a Pickle
    class TestCaseCreated < Core::Event.new(:test_case, :pickle)
      attr_reader :test_case
      attr_reader :pickle
    end
  end
end
