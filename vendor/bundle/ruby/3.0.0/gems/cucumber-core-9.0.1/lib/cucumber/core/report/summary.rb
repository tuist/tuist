# frozen_string_literal: true
module Cucumber
  module Core
    module Report
      class Summary
        attr_reader :test_cases, :test_steps

        def initialize(event_bus)
          @previous_test_case = nil
          @test_cases = Test::Result::Summary.new
          @test_steps = Test::Result::Summary.new
          subscribe_to(event_bus)
        end

        def ok?(be_strict = Test::Result::StrictConfiguration.new)
          test_cases.ok?(be_strict)
        end

        private

        def subscribe_to(event_bus)
          event_bus.on(:test_case_finished) do |event|
            if event.test_case != @previous_test_case
              @previous_test_case = event.test_case
              event.result.describe_to test_cases
            elsif event.result.passed? || event.result.skipped?
              test_cases.flaky
              test_cases.decrement_failed
            end
          end
          event_bus.on(:test_step_finished) do |event|
            event.result.describe_to test_steps unless event.test_step.hook?
          end
          self
        end
      end
    end
  end
end
