require 'cucumber/core/events'

module Cucumber
  module Events
    # Signals that a {Cucumber::Core::Test::Step} is about to be executed
    class TestStepStarted < Core::Events::TestStepStarted
      # @return [Cucumber::Core::Test::Step] the test step to be executed
      attr_reader :test_step
    end
  end
end
