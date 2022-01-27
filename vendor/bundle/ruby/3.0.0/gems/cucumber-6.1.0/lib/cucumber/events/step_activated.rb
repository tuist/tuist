# frozen_string_literal: true

require 'cucumber/core/events'

module Cucumber
  module Events
    # Event fired when a step is activated
    class StepActivated < Core::Event.new(:test_step, :step_match)
      # The test step that was matched.
      #
      # @return [Cucumber::Core::Test::Step]
      attr_reader :test_step

      # Information about the matching definition.
      #
      # @return [Cucumber::StepMatch]
      attr_reader :step_match

      # @private
      def initialize(test_step, step_match)
        @test_step = test_step
        @step_match = step_match
      end
    end
  end
end
