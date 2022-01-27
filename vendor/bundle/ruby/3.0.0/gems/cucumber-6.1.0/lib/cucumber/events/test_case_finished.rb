require 'cucumber/core/events'

module Cucumber
  module Events
    # Signals that a {Cucumber::Core::Test::Case} has finished executing
    class TestCaseFinished < Core::Events::TestCaseFinished
      # @return [Cucumber::Core::Test::Case] that was executed
      attr_reader :test_case

      # @return [Cucumber::Core::Test::Result] the result of running the {Cucumber::Core::Test::Case}
      attr_reader :result
    end
  end
end
