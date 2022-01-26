require 'cucumber/core/events'

module Cucumber
  module Events
    # Signals that a {Cucumber::Core::Test::Case} is about to be executed
    class TestCaseStarted < Core::Events::TestCaseStarted
      # @return [Cucumber::Core::Test::Case] the test case to be executed
      attr_reader :test_case
    end
  end
end
