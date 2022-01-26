# frozen_string_literal: true

require 'cucumber/core/filter'
require 'cucumber/step_match'
require 'cucumber/events'
require 'cucumber/errors'

module Cucumber
  module Filters
    class ActivateSteps < Core::Filter.new(:step_match_search, :configuration)
      def test_case(test_case)
        CaseFilter.new(test_case, step_match_search, configuration).test_case.describe_to receiver
      end

      class CaseFilter
        def initialize(test_case, step_match_search, configuration)
          @original_test_case = test_case
          @step_match_search = step_match_search
          @configuration = configuration
        end

        def test_case
          @original_test_case.with_steps(new_test_steps)
        end

        private

        def new_test_steps
          @original_test_case.test_steps.map(&method(:attempt_to_activate))
        end

        def attempt_to_activate(test_step)
          find_match(test_step).activate(test_step)
        end

        def find_match(test_step)
          FindMatch.new(@step_match_search, @configuration, test_step).result
        end

        class FindMatch
          def initialize(step_match_search, configuration, test_step)
            @step_match_search = step_match_search
            @configuration = configuration
            @test_step = test_step
          end

          def result
            begin
              return NoStepMatch.new(test_step, test_step.text) unless matches.any?
            rescue Cucumber::Ambiguous => e
              return AmbiguousStepMatch.new(e)
            end
            configuration.notify :step_activated, test_step, match
            return SkippingStepMatch.new if configuration.dry_run?
            match
          end

          private

          attr_reader :step_match_search, :configuration, :test_step
          private :step_match_search, :configuration, :test_step

          def match
            matches.first
          end

          def matches
            step_match_search.call(test_step.text)
          end
        end
      end
    end
  end
end
