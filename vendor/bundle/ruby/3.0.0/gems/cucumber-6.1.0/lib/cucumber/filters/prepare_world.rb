# frozen_string_literal: true

require 'cucumber/core/filter'
require 'cucumber/core/test/location'
require 'cucumber/running_test_case'

module Cucumber
  module Filters
    class PrepareWorld < Core::Filter.new(:runtime)
      def test_case(test_case)
        CaseFilter.new(runtime, test_case).test_case.describe_to receiver
      end

      class CaseFilter
        def initialize(runtime, original_test_case)
          @runtime = runtime
          @original_test_case = original_test_case
        end

        def test_case
          init_scenario = Cucumber::Hooks.around_hook do |continue|
            @runtime.begin_scenario(scenario)
            continue.call
            @runtime.end_scenario(scenario)
          end
          around_hooks = [init_scenario] + @original_test_case.around_hooks

          @original_test_case.with_around_hooks(around_hooks).with_steps(@original_test_case.test_steps)
        end

        private

        def scenario
          @scenario ||= RunningTestCase.new(test_case)
        end
      end
    end
  end
end
