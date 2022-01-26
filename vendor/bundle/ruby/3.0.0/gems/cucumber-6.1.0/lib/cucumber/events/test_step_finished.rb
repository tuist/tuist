require 'cucumber/core/events'

module Cucumber
  module Events
    # Signals that a {Cucumber::Core::Test::Step} has finished executing
    class TestStepFinished < Core::Events::TestStepFinished
      # @return [Cucumber::Core::Test::Step] the test step that was executed
      attr_reader :test_step

      # @return [Cucumber::Core::Test::Result] the result of running the {Cucumber::Core::Test::Step}
      attr_reader :result
    end
  end
end
